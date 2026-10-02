extends SceneTree
## Battle balance harness (#4): Aurel Crown's win % for a matrix of matchups x ground, each cell
## fought `--seeds` times with the real AutoBattleResolver on seeded battles. Prints markdown.
##
##   godot --headless --path . -s tools/balance/matchups.gd -- --seeds 400
##
## Options (all optional):
##   --seeds N      battles per cell (default 400), on seeds S+1 .. S+N
##   --seed S       base seed (default 0)
##   --only GROUP   only one group of matchups: starting, pair, mixed or commander
##   --grounds K,K  only these grounds (keys from Balance.GROUNDS, e.g. open,forest_crown)
##   --samples N    also print the first N battle reports of the starting armies on open ground
##   --compositions GOLD   also print a matrix of army styles (Balance.STYLES) at GOLD gold each,
##                  commanders included, on open ground: how big armies of each make-up fare
##   --out PATH     also write the markdown to PATH
##   --crown-mandates ID,ID   fight with these mandates on the Aurel Crown side (M2-2), e.g. royal_armories
##   --clans-mandates ID,ID   the same for the Thornmane Clans, e.g. drilled_ranks,blood_frenzy
##   --crown-ruler RULER:KEPT  add that ruler, with that kept power, beside the Aurel Crown army in every
##                  battle (e.g. aurel_king:10); --clans-ruler the same for the Thornmane Clans
##                  Mandates and rulers move units off the breakpoint-safe stats of #41, so this is how
##                  to see what they shift. Without them every number is the M1 battle's.
##
## Matchups (tools/balance/balance.gd, built from the current costs in data/factions.gd): the starting
## armies (with and without commanders), equal-gold pure-unit fights for every cross-faction pair at
## about 100 gold, mixed armies at 50 and 100 gold, and commander-led armies. Grounds: open (both
## arrived together: no defender, no terrain), then plains, forest, hills and a fort with each side
## defending. The tables are followed by the targets of the balance pass and where each stands, and
## by how often each "why" factor led a battle's summary.

const Balance := preload("res://tools/balance/balance.gd")
const GROUPS := ["starting", "pair", "mixed", "commander"]


func _initialize() -> void:
	var opts := _parse(OS.get_cmdline_user_args())
	if opts.has("error"):
		printerr("matchups: %s" % opts.error)
		printerr("usage: godot --headless --path . -s tools/balance/matchups.gd -- [--seeds 400] [--seed 0] [--only starting|pair|mixed|commander] [--grounds open,forest_crown] [--samples N] [--out report.md]")
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var state := Balance.new_state()
	if not opts.mandates.is_empty() or not opts.rulers.is_empty():
		var errors := []
		state = Balance.new_state_with(opts.mandates, opts.rulers, errors)
		if state == null:
			printerr("matchups: %s" % " ".join(errors))
			quit(2)
			return
	var ruler_fids: Array = opts.rulers.keys()
	var grounds := []
	for g in Balance.GROUNDS:
		if opts.grounds.is_empty() or opts.grounds.has(g.key):
			grounds.append(g)
	var rows := []
	for m in Balance.matchups(state):
		if not opts.only.is_empty() and m.group != opts.only:
			continue
		var cells := {}
		for g in grounds:
			cells[g.key] = Balance.batch(state, m.crown, m.clans, g, opts.seeds, opts.seed, 0, ruler_fids)
		rows.append({"m": m, "cells": cells})
	var seconds := (Time.get_ticks_msec() - started) / 1000.0

	var L := []
	L.append("## Battle balance: Aurel Crown win %% (%d seeded battles per cell)" % opts.seeds)
	L.append("")
	if not opts.mandates.is_empty() or not opts.rulers.is_empty():
		L.append(_m2_line(state, opts))
		L.append("")
	L.append(_unit_table(state))
	L.append("")
	var head := "| Matchup (Crown vs Clans, gold) |"
	var rule := "|---|"
	for g in grounds:
		head += " %s |" % g.label
		rule += "---|"
	L.append(head)
	L.append(rule)
	for row in rows:
		var m: Dictionary = row.m
		var line := "| %s: %s (%d) vs %s (%d) |" % [m.name, Balance.describe(state, Balance.CROWN, m.crown), Balance.cost(state, Balance.CROWN, m.crown),
			Balance.describe(state, Balance.CLANS, m.clans), Balance.cost(state, Balance.CLANS, m.clans)]
		for g in grounds:
			line += " %.1f |" % row.cells[g.key].crown_pct
		L.append(line)
	L.append("")
	L.append(_battle_shape(rows, grounds))
	L.append("")
	L.append(_targets(rows, grounds))
	L.append("")
	L.append(_why(rows, grounds))
	if opts.compositions > 0:
		L.append("")
		L.append(_compositions(state, opts.compositions, mini(opts.seeds, 200), opts.seed, ruler_fids))
	if opts.samples > 0:
		L.append("")
		L.append("### Sample reports: starting armies, open ground")
		var start: Dictionary = Balance.matchups(state)[0]
		var b := Balance.batch(state, start.crown, start.clans, Balance.ground("open"), opts.samples, opts.seed, opts.samples, ruler_fids)
		for rep in b.reports:
			L.append("")
			L.append("```")
			L.append("\n".join(rep.lines))
			L.append("```")
	L.append("")
	L.append("Run: `--seeds %d --seed %d%s%s`, %.1f s." % [opts.seeds, opts.seed, (" --only " + opts.only) if not opts.only.is_empty() else "",
		opts.m2_args, seconds])
	var md := "\n".join(L)
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("matchups: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	quit(0)


## The roster's numbers as they fight (RulerRules.unit_stats: with the side's mandates, if any).
func _unit_table(state: GameState) -> String:
	var L := ["| Unit | Faction | hp | attack | defense | morale | cost | trait |", "|---|---|---|---|---|---|---|---|"]
	for f in state.factions:
		var types: Array = f.unit_types.duplicate()
		types.append(f.commander_type)
		for ut in types:
			var us := RulerRules.unit_stats(state, f.id, ut.id)
			L.append("| %s | %s | %d | %d | %d | %d | %d | %s: %s |" % [ut.name, f.faction_name, us.hp, us.attack, us.defense,
				ut.morale, us.cost, ut.trait_id, ut.trait_description])
	return "\n".join(L)


## What the run fought with (M2-2): each side's mandates and ruler.
func _m2_line(state: GameState, opts: Dictionary) -> String:
	var parts := []
	for fid in [Balance.CROWN, Balance.CLANS]:
		var f := state.find_faction(fid)
		var names := []
		for mid in opts.mandates.get(fid, []):
			names.append(RulerRules.mandate_name(mid))
		var bit := "%s: %s" % [f.faction_name, ", ".join(names) if not names.is_empty() else "no mandates"]
		if opts.rulers.has(fid):
			bit += ", with %s (%d kept power) in every battle" % [RulerRules.current_name(state, fid), f.kept_power]
		parts.append(bit)
	return "**With rulers (M2-2):** %s." % "; ".join(parts)


## Mean rounds and how battles ended, on open ground.
func _battle_shape(rows: Array, grounds: Array) -> String:
	var key: String = "open" if grounds.any(func(g): return g.key == "open") else grounds[0].key
	var L := ["| Matchup (%s) | mean rounds | rout | destroyed | mutual rout | round cap |" % key, "|---|---|---|---|---|---|"]
	for row in rows:
		var c: Dictionary = row.cells[key]
		var n: int = c.n
		L.append("| %s | %.1f | %d%% | %d%% | %d%% | %d%% |" % [row.m.name, c.rounds, _pct(c.ends.get("rout", 0), n),
			_pct(c.ends.get("destroyed", 0), n), _pct(c.ends.get("mutual", 0), n), _pct(c.ends.get("round_cap", 0), n)])
	return "\n".join(L)


## Where each target of the balance pass stands.
func _targets(rows: Array, grounds: Array) -> String:
	var L := ["### Targets"]
	var has := func(k): return grounds.any(func(g): return g.key == k)
	if has.call("open"):
		for row in rows:
			if row.m.name == "Starting armies":
				var p: float = row.cells.open.crown_pct
				L.append("- (a) Starting armies, open: Crown %.1f%%, Clans %.1f%% (target: each 40-60) %s" % [p, 100.0 - p, _ok(p >= 40.0 and p <= 60.0)])
		var pairs := rows.filter(func(r): return r.m.group == "pair")
		if not pairs.is_empty():
			var vals: Array = pairs.map(func(r): return r.cells.open.crown_pct)
			var mean: float = vals.reduce(func(a, b): return a + b, 0.0) / vals.size()
			L.append("- (b) Equal-gold pairs, open: mean %.1f%%, min %.1f%%, max %.1f%% (target: mean 30-70, every pair 20-80) %s" % [
				mean, vals.min(), vals.max(), _ok(mean >= 30.0 and mean <= 70.0 and vals.min() >= 20.0 and vals.max() <= 80.0)])
	# Terrain: how much holding forest, hills or a fort raises the defender's win % over holding plains.
	for t in ["forest", "hills", "fort"]:
		var parts := []
		for side in [["crown", Balance.CROWN, "Crown"], ["clans", Balance.CLANS, "Clans"]]:
			var k: String = "%s_%s" % [t, side[0]]
			var base: String = "plains_%s" % side[0]
			if not has.call(k) or not has.call(base):
				continue
			var shifts := []
			var extremes := 0
			for row in rows:
				var here: float = _defender_pct(row.cells[k], side[1])
				var plain: float = _defender_pct(row.cells[base], side[1])
				shifts.append(here - plain)
				if here <= 0.5 or here >= 99.5:
					extremes += 1
			var mean: float = shifts.reduce(func(a, b): return a + b, 0.0) / shifts.size()
			parts.append("%s defending %+.1f points (from %+.1f to %+.1f; %d cells at 0 or 100)" % [side[2], mean, shifts.min(), shifts.max(), extremes])
		if not parts.is_empty():
			L.append("- (c) %s vs plains, defender's win %%: %s (target: about +10 to +25, never 0 or 100)" % [t.capitalize(), "; ".join(parts)])
	if has.call("open"):
		var cmd := rows.filter(func(r): return r.m.group == "commander")
		var bits := []
		for r in cmd:
			bits.append("%s %.1f%%" % [r.m.name, r.cells.open.crown_pct])
		if not bits.is_empty():
			L.append("- (d) Commander-led, open (Crown win %%): %s" % ", ".join(bits))
	return "\n".join(L)


## Aurel Crown's win % for each Crown army style against each Thornmane style, `gold` gold each with
## their commanders, on open ground: whether one make-up beats everything once armies are big.
func _compositions(state: GameState, gold: int, seeds: int, base_seed: int, ruler_fids: Array = []) -> String:
	var clans_styles: Array = Balance.STYLES[Balance.CLANS]
	var L := ["### Army styles at %d gold each, with commanders, open ground (Aurel Crown win %%, %d battles per cell)" % [gold, seeds]]
	var head := "| Aurel Crown style vs Thornmane Clans style |"
	var rule := "|---|"
	for st in clans_styles:
		head += " %s |" % st[0]
		rule += "---|"
	L.append(head)
	L.append(rule)
	for cs in Balance.STYLES[Balance.CROWN]:
		var crown := Balance.ratio_army(state, Balance.CROWN, cs[1], gold)
		var line := "| %s |" % cs[0]
		for ks in clans_styles:
			var clans := Balance.ratio_army(state, Balance.CLANS, ks[1], gold)
			line += " %.0f |" % Balance.batch(state, crown, clans, Balance.ground("open"), seeds, base_seed, 0, ruler_fids).crown_pct
		L.append(line)
	return "\n".join(L)


## How often each factor was the first reason of a battle's "why", and how often it was cited at all.
func _why(rows: Array, grounds: Array) -> String:
	var top := {}
	var cited := {}
	var battles := 0
	for row in rows:
		for g in grounds:
			var c: Dictionary = row.cells[g.key]
			battles += c.n
			for k in c.top:
				var id: String = k.split("|")[0]
				top[id] = int(top.get(id, 0)) + c.top[k]
			for k in c.cited:
				var id: String = k.split("|")[0]
				cited[id] = int(cited.get(id, 0)) + c.cited[k]
	var ids: Array = cited.keys()
	ids.sort_custom(func(a, b): return cited[a] > cited[b] if cited[a] != cited[b] else a < b)
	var parts := []
	for id in ids:
		parts.append("%s %d%% (first %d%%)" % [id, _pct(cited[id], battles), _pct(top.get(id, 0), battles)])
	return "### Why factors over all %d battles\nCited (and first reason): %s." % [battles, ", ".join(parts)]


static func _defender_pct(cell: Dictionary, fid: String) -> float:
	return cell.crown_pct if fid == Balance.CROWN else 100.0 - cell.crown_pct


static func _pct(n, total) -> int:
	return 0 if int(total) == 0 else roundi(100.0 * float(n) / float(total))


static func _ok(good: bool) -> String:
	return "**ok**" if good else "**off**"


func _parse(args: PackedStringArray) -> Dictionary:
	var opts := {"seeds": 400, "seed": 0, "only": "", "grounds": [], "samples": 0, "compositions": 0, "out": "", "mandates": {},
		"rulers": {}, "m2_args": ""}
	var i := 0
	while i < args.size():
		var key := args[i]
		if i + 1 >= args.size():
			return {"error": "%s needs a value" % key}
		var value := args[i + 1]
		i += 2
		match key:
			"--seeds":
				if not value.is_valid_int() or value.to_int() < 1:
					return {"error": "--seeds must be a positive whole number"}
				opts.seeds = value.to_int()
			"--seed":
				if not value.is_valid_int():
					return {"error": "--seed must be a whole number"}
				opts.seed = value.to_int()
			"--only":
				if not GROUPS.has(value):
					return {"error": "--only must be one of %s" % ", ".join(GROUPS)}
				opts.only = value
			"--grounds":
				for k in value.split(","):
					if Balance.ground(k).is_empty():
						return {"error": "unknown ground %s" % k}
					opts.grounds.append(k)
			"--samples":
				if not value.is_valid_int() or value.to_int() < 0:
					return {"error": "--samples must be a whole number"}
				opts.samples = value.to_int()
			"--compositions":
				if not value.is_valid_int() or value.to_int() < 50:
					return {"error": "--compositions must be a gold budget of at least 50"}
				opts.compositions = value.to_int()
			"--out":
				opts.out = value
			"--crown-mandates", "--clans-mandates":
				var fid: String = Balance.CROWN if key == "--crown-mandates" else Balance.CLANS
				var ids := []
				for mid in value.split(","):
					if RulerRules.mandate_data(mid).is_empty():
						return {"error": "unknown mandate %s" % mid}
					ids.append(mid)
				opts.mandates[fid] = ids
				opts.m2_args += " %s %s" % [key, value]
			"--crown-ruler", "--clans-ruler":
				var fid: String = Balance.CROWN if key == "--crown-ruler" else Balance.CLANS
				var bits := value.split(":")
				if bits.size() != 2 or not RulerRules.rulers_for(fid).has(bits[0]) or not bits[1].is_valid_int():
					return {"error": "%s needs RULER:KEPT with one of %s" % [key, ", ".join(RulerRules.rulers_for(fid))]}
				opts.rulers[fid] = [bits[0], bits[1].to_int()]
				opts.m2_args += " %s %s" % [key, value]
			_:
				return {"error": "unknown option %s" % key}
	return opts
