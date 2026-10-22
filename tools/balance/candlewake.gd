extends SceneTree
## CW-2's micro-benchmarks (#253, design/CANDLEWAKE.md §9): the Candlewake's win % against the Crown and the Clans, each cell
## fought `--seeds` times with the real AutoBattleResolver on seeded battles. Prints markdown.
##
##   godot --headless --path . -s tools/balance/candlewake.gd -- --seeds 200 [--out PATH]
##
## Rows: each Candlewake unit against each Crown and Clans unit at equal gold (about PAIR_GOLD a side, whole units, a commander
## counting as its own line), mixed armies at MIXED_GOLD a side, and the Clans' Tuskers with Blood Frenzy (a mandate). Columns:
## flames 0 to 3 on open ground, then flame 1 on each ground with each side defending (forest, hills, a fort). The Red Wake's
## flame 4 waits for CW-4, Iron Hide for paths (CW-4's Amber Saints and the Crown's Iron Knights), Shield Wall is in every pair
## with two or more Spearmen. The gate (§9): at flame 1, equal-gold pairs between PAIR_BAND and mixed armies within MIXED_BAND,
## on open ground. tests/test_cw2_benchmarks.gd runs the gate with fewer seeds.

const Balance := preload("res://tools/balance/balance.gd")
const WAKE := "candlewake"
const FOES := ["kingdom", "beasts"]
const PAIR_GOLD := 100
const MIXED_GOLD := 100
const PAIR_BAND := [20.0, 80.0]
const MIXED_BAND := [30.0, 70.0]
const FLAMES := [0, 1, 2, 3]
## Grounds: [key, label, province, who defends ("wake", "foe" or "")].
const GROUNDS := [["open", "Open", "rivermarch", ""], ["forest_wake", "Forest, Candlewake defend", "greenglade", "wake"],
	["forest_foe", "Forest, foe defends", "greenglade", "foe"], ["hills_wake", "Hills, Candlewake defend", "highcrag", "wake"],
	["hills_foe", "Hills, foe defends", "highcrag", "foe"], ["fort_wake", "Fort, Candlewake defend", "", "wake"],
	["fort_foe", "Fort, foe defends", "", "foe"]]
const MIX := {"candlewake": ["wickwardens", "gleaners", "wickwardens", "hundred_wick", "gleaners", "wickwardens"],
	"kingdom": ["spearmen", "crossbowmen", "knights", "spearmen", "crossbowmen", "spearmen"],
	"beasts": ["tuskers", "fangthrowers", "war_bear", "tuskers", "fangthrowers", "tuskers"]}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := 200
	var i := args.find("--seeds")
	if i >= 0 and i + 1 < args.size():
		seeds = int(args[i + 1])
	var started := Time.get_ticks_msec()
	var md := report(seeds)
	md += "\n%d battles a cell; %.1f s.\n" % [seeds, (Time.get_ticks_msec() - started) / 1000.0]
	i = args.find("--out")
	if i >= 0 and i + 1 < args.size():
		var f := FileAccess.open(args[i + 1], FileAccess.WRITE)
		f.store_string(md)
		f.close()
	print(md)
	quit(0)


## A game of the Candlewake and `foe` (no armies), with `builds` for rulers' mandates (Blood Frenzy) when given.
static func state_for(foe: String, builds: Dictionary = {}) -> GameState:
	var s := GameState.create(1, [foe, WAKE], {"rulers": not builds.is_empty()}, builds, [])
	s.armies.clear()
	return s


## Whole units of `type_id` for about `gold` (at least 1), at `owner`'s prices in `state`.
static func units_for(state: GameState, owner: String, type_id: String, gold: int) -> Array:
	var price := TurnResolver.recruit_cost(state, owner, type_id)
	var n := maxi(1, roundi(float(gold) / maxi(1, price)))
	var out := []
	for k in n:
		out.append(type_id)
	return out


## A mixed army of `owner` for about `gold`, filled from MIX in turn.
static func mixed(state: GameState, owner: String, gold: int) -> Array:
	var out := []
	var left := gold
	var cycle: Array = MIX[owner]
	var misses := 0
	var k := 0
	while misses < cycle.size():
		var c := TurnResolver.recruit_cost(state, owner, String(cycle[k % cycle.size()]))
		if c <= left:
			out.append(cycle[k % cycle.size()])
			left -= c
			misses = 0
		else:
			misses += 1
		k += 1
	return out


static func _army(state: GameState, owner: String, ids: Array, id: String, flame: int = -1) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = owner
	var f := state.find_faction(owner)
	for type_id in ids:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			var u := Unit.new(ut, owner)
			u.current_hp = RulerRules.unit_max_hp(state, u)
			a.units.append(u)
	if WickRules.carries_flame(a):
		a.flame = flame
	return a


## The Candlewake's win % of `seeds` battles: `wake_ids` at `flame` against `foe_ids`, on ground `g` (a GROUNDS row).
static func win_pct(state: GameState, foe: String, wake_ids: Array, foe_ids: Array, flame: int, g: Array, seeds: int) -> float:
	var pid := String(g[2])
	if pid.is_empty():
		pid = state.find_faction(WAKE if String(g[3]) == "wake" else foe).capital  # a fort: the defender's capital
	var province := state.find_province(pid)
	var wake := _army(state, WAKE, wake_ids, "candlewake-1", flame)
	var them := _army(state, foe, foe_ids, "%s-1" % foe)
	wake.location = pid
	them.location = pid
	var defender := ""
	if String(g[3]) == "wake":
		defender = WAKE
	elif String(g[3]) == "foe":
		defender = foe
	var sides := [{"faction": WAKE, "armies": [wake]}, {"faction": foe, "armies": [them]}]
	sides.sort_custom(func(a, b): return String(a.faction) < String(b.faction))
	var ctx := {"kind": "province", "defender": defender, "province": province, "province_ids": [pid], "state": state}
	var wins := 0
	for i in seeds:
		if AutoBattleResolver.fight(sides, ctx, SeededRNG.new(i + 1)).result.winner == WAKE:
			wins += 1
	return 100.0 * wins / maxi(1, seeds)


## Every row: [{"label", "foe", "kind" ("pair" | "mixed" | "frenzy"), "wake", "them", "cells": {"<flame>": pct on open ground,
## "<ground key>": pct at flame 1}}].
static func rows(seeds: int, grounds: bool = true) -> Array:
	var out := []
	for foe in FOES:
		var s := state_for(foe)
		var mine: Array = FactionData.row(WAKE).unit_types.map(func(u): return String(u.id)) + [String(FactionData.row(WAKE).commander.id)]
		var theirs: Array = FactionData.row(foe).unit_types.map(func(u): return String(u.id)) + [String(FactionData.row(foe).commander.id)]
		for w in mine:
			for t in theirs:
				out.append(_row(s, foe, "pair", units_for(s, WAKE, w, PAIR_GOLD), units_for(s, foe, t, PAIR_GOLD), seeds, grounds))
		out.append(_row(s, foe, "mixed", mixed(s, WAKE, MIXED_GOLD), mixed(s, foe, MIXED_GOLD), seeds, grounds))
	var fs := state_for("beasts", {"beasts": {"ruler": "fang_chieftain", "mandates": ["blood_frenzy"]}})
	out.append(_row(fs, "beasts", "frenzy", mixed(fs, WAKE, MIXED_GOLD), units_for(fs, "beasts", "tuskers", MIXED_GOLD), seeds, grounds))
	return out


static func _row(s: GameState, foe: String, kind: String, wake_ids: Array, foe_ids: Array, seeds: int, grounds: bool) -> Dictionary:
	var cells := {}
	for fl in FLAMES:
		cells[str(fl)] = win_pct(s, foe, wake_ids, foe_ids, fl, GROUNDS[0], seeds)
	if grounds:
		for g in GROUNDS.slice(1):
			cells[String(g[0])] = win_pct(s, foe, wake_ids, foe_ids, 1, g, seeds)
	return {"label": "%s vs %s" % [Balance.describe(s, WAKE, wake_ids), Balance.describe(s, foe, foe_ids)], "foe": foe, "kind": kind,
		"wake": wake_ids, "them": foe_ids, "cells": cells}


## The rows that miss the gate at flame 1 on open ground (§9): [{"label", "pct", "band"}].
static func misses(all: Array) -> Array:
	var out := []
	for r in all:
		var band: Array = PAIR_BAND if String(r.kind) == "pair" else MIXED_BAND
		var pct := float(r.cells["1"])
		if pct < float(band[0]) or pct > float(band[1]):
			out.append({"label": r.label, "pct": pct, "band": band})
	return out


static func report(seeds: int) -> String:
	var all := rows(seeds)
	var L := ["## The Candlewake's micro-benchmarks (CW-2, design/CANDLEWAKE.md §9): Candlewake win %", ""]
	var head := "| Matchup (gold a side) |"
	var rule := "|---|"
	for fl in FLAMES:
		head += " flame %d |" % fl
		rule += "---|"
	for g in GROUNDS.slice(1):
		head += " %s (flame 1) |" % g[1]
		rule += "---|"
	L.append(head)
	L.append(rule)
	for r in all:
		var line := "| %s%s |" % [r.label, " (Blood Frenzy)" if String(r.kind) == "frenzy" else ""]
		for fl in FLAMES:
			line += " %.1f |" % float(r.cells[str(fl)])
		for g in GROUNDS.slice(1):
			line += " %.1f |" % float(r.cells[String(g[0])])
		L.append(line)
	L.append("")
	var miss := misses(all)
	L.append("**The gate (flame 1, open ground):** equal-gold pairs %d-%d%%, mixed armies %d-%d%%: %s." % [int(PAIR_BAND[0]), int(PAIR_BAND[1]),
		int(MIXED_BAND[0]), int(MIXED_BAND[1]), "every row holds" if miss.is_empty() else "%d miss" % miss.size()])
	for m in miss:
		L.append("- %s: %.1f%% (band %d-%d%%)" % [m.label, float(m.pct), int(m.band[0]), int(m.band[1])])
	return "\n".join(L) + "\n"
