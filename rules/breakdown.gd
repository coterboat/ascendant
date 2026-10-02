class_name Breakdown
## Number breakdowns for tooltips: where every number the UI shows comes from.
## Pure functions over GameState (no Node dependencies). Each returns the same shape:
##   {"title": String, "description": String, "lines": [{"label", "value", "note"}],
##    "total_label": String, "total": int}
## and the total always equals the sum of the line values, so a tooltip can show
## "base + modifiers = total" and never disagree with the number on screen.
## The math is taken from the rules code (TurnResolver.income_of, StubBattleResolver.army_strength),
## never redone here, and the descriptions come from the model describe() strings and RulesCodex.


## Income a province earns its owner each turn: base income plus modifiers (none exist in M1).
static func province_income(state: GameState, province_id: String) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null:
		return _make("Income", "This place is not on the map.", [], "Income per turn", 0)
	var lines := [
		_line("Base income of %s" % p.name, p.income, "set by the map"),
		_line("Modifiers", 0, "none yet: terrain, forts and capitals do not change income in this milestone"),
	]
	var owner_text := "Nobody owns it, so nobody earns this gold." if p.owner.is_empty() \
		else "%s earns this gold at the end of each turn." % _faction_name(state, p.owner)
	var desc := "%s %s %s" % [Province.describe("income"), owner_text, RulesCodex.text("income")]
	return _make("Income of %s" % p.name, desc, lines, "Income per turn", p.income)


## A faction's gold now, plus the income of each province it owns, giving its gold next turn
## before any recruits are paid for. Province lines use TurnResolver.income_of (same as the resolver).
static func gold(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _make("Gold", "This faction is not in the game.", [], "Gold next turn", 0)
	var lines := [_line("Gold now", f.gold, "in the treasury")]
	var income: Dictionary = TurnResolver.income_of(state, faction_id)
	var ids: Array = income.by_province.keys()
	ids.sort()
	for pid in ids:
		lines.append(_line("Income from %s" % _province_name(state, pid), income.by_province[pid], "a province you own"))
	var desc := "%s Gold next turn assumes you recruit nothing and no provinces change hands. %s" % [
		Faction.describe("gold"), RulesCodex.text("income")]
	return _make("Gold of %s" % f.faction_name, desc, lines, "Gold next turn (before recruits)", f.gold + income.total)


## How many units an army has, by unit type. The commander leads the army but is not counted,
## the same way the army labels in the turn report count units.
static func army_units(state: GameState, army_id: String) -> Dictionary:
	var army := state.find_army(army_id)
	if army == null:
		return _make("Units", "This army is not in the game.", [], "Units", 0)
	var counts := {}
	var order := []
	for u in army.units:
		if not counts.has(u.type.name):
			counts[u.type.name] = 0
			order.append(u.type.name)
		counts[u.type.name] += 1
	var lines := []
	for type_name in order:
		lines.append(_line(type_name, counts[type_name], ""))
	var desc := "Units in this army. Each unit fights in battles and can be lost."
	if army.commander:
		desc += " The %s leads the army and is not counted as a unit." % army.commander.type.name
	else:
		desc += " This army has no commander."
	return _make("Units in the %s" % TurnResolver.army_label(state, army), desc, lines, "Units", army.units.size())


## An army's strength: attack + defense of every unit and its commander (StubBattleResolver.army_strength).
## A size guide only; real battles (AutoBattleResolver) don't use it, and RulesCodex "army_strength" says so.
static func army_strength(state: GameState, army_id: String) -> Dictionary:
	var army := state.find_army(army_id)
	if army == null:
		return _make("Strength", "This army is not in the game.", [], "Strength", 0)
	var lines := []
	for u in army.units:
		lines.append(_line(u.type.name, u.type.attack + u.type.defense, "attack %d + defense %d" % [u.type.attack, u.type.defense]))
	if army.commander:
		var c := army.commander.type
		lines.append(_line("%s (commander)" % c.name, c.attack + c.defense, "attack %d + defense %d" % [c.attack, c.defense]))
	return _make("Strength of the %s" % TurnResolver.army_label(state, army), RulesCodex.text("army_strength"),
		lines, "Strength", StubBattleResolver.army_strength(army))


## How many units of one type an army has, with that unit type's stats explained.
static func unit_count(state: GameState, army_id: String, unit_type_name: String) -> Dictionary:
	var army := state.find_army(army_id)
	if army == null:
		return _make(unit_type_name, "This army is not in the game.", [], unit_type_name, 0)
	var count := 0
	var ut: UnitType = null
	for u in army.units:
		if u.type.name == unit_type_name:
			count += 1
			ut = u.type
	var desc := "How many %s this army has." % unit_type_name
	if ut:
		desc += " " + unit_type_description(ut)
	return _make(unit_type_name, desc, [_line("%s in this army" % unit_type_name, count, "")], unit_type_name, count)


## Plain description of a unit type's stats, using the UnitType describe() strings.
static func unit_type_description(ut: UnitType) -> String:
	return "%s: hit points %d (%s) Attack %d (%s) Defense %d (%s) Morale %d (%s) Recruit cost %d gold. Trait %s: %s" % [
		ut.name, ut.hp, UnitType.describe("hp"), ut.attack, UnitType.describe("attack"),
		ut.defense, UnitType.describe("defense"), ut.morale, UnitType.describe("morale"),
		ut.cost, ut.trait_id, ut.get_trait_desc()]


## The turn being ordered, 1-based like every turn number players see (GameSession.turn_number()):
## turn 1 is the first, and each resolved turn (TurnResolver.resolve) adds one.
static func turn(state: GameState) -> Dictionary:
	var number := state.current_turn + 1
	return _make("Turn %d" % number,
		"The turn you are giving orders for. Turn 1 is the first, and each resolved turn adds one. %s" % RulesCodex.text("phase_order"),
		[_line("Turns resolved so far", state.current_turn, ""), _line("This turn", 1, "the turn being ordered now")],
		"Current turn", number)


# --- rulers and mandates (M2, #29) ----------------------------------------------------------------
# Every number comes from RulerRules, never redone here. These breakdowns also carry a "codex" key
# naming the RulesCodex entry that explains them (TooltipText.codex_for uses it).

## A faction's kept power (§7.1): the pool of 10, minus each mandate chosen before the game, minus
## each mid-game sacrifice, minus what successions cost (the remainder, so the lines always sum up).
static func kept_power(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return _coded(_make("Kept power", "This faction has no ruler in this game.", [], "Kept power", 0), "kept_power")
	var lines := [_line("Power pool", RulerData.POWER_POOL, "every ruler starts with %d" % RulerData.POWER_POOL)]
	var sacrificed := {}
	for sac in f.sacrifices:
		sacrificed[str(sac.get("mandate", ""))] = true
	for mid in f.mandates:
		if not sacrificed.has(mid):
			lines.append(_line(RulerRules.mandate_name(mid), -RulerRules.mandate_cost(mid), "a mandate chosen before the game"))
	for sac in f.sacrifices:
		lines.append(_line("%s, sacrificed on turn %d" % [RulerRules.mandate_name(str(sac.get("mandate", ""))), int(sac.get("turn", 0))],
			-int(sac.get("cost", 0)), "its price +%d for a mid-game sacrifice" % MandateData.SACRIFICE_PREMIUM))
	var listed := sum_of_lines({"lines": lines})
	if listed != f.kept_power:
		lines.append(_line("Successions", f.kept_power - listed, "power lost when a ruler died and a successor took over"))
	var desc := "%s keeps %d of its %d power. %s" % [RulerRules._cap(RulerRules.current_name(state, faction_id)),
		f.kept_power, RulerData.POWER_POOL, RulesCodex.text("kept_power")]
	return _coded(_make("Kept power of %s" % RulerRules.current_name(state, faction_id), desc, lines, "Kept power", f.kept_power), "kept_power")


## Kept power of a build before the game (the build screen's power bar): pool - each mandate's cost.
## `build` is {"ruler", "mandates"} or a preset id. An empty build keeps all 10.
static func build_kept_power(build) -> Dictionary:
	var b := RulerRules.normalize_build(build)
	var lines := [_line("Power pool", RulerData.POWER_POOL, "every ruler starts with %d" % RulerData.POWER_POOL)]
	var seen := {}
	for mid in b.mandates:
		if seen.has(mid):
			continue
		seen[mid] = true
		lines.append(_line(RulerRules.mandate_name(mid), -RulerRules.mandate_cost(mid), "mandate"))
	return _coded(_make("Kept power", RulesCodex.text("kept_power"), lines, "Kept power", RulerRules.kept_after(b)), "kept_power")


## One of a ruler's numbers at `kept` power (§7.1): "hp" (maximum hit points), "attack" or "defense"
## as base + what kept power adds, e.g. "Attack 14 = base 9 + 5 from 10 kept power"; "morale" is its
## own morale, used when it fights with no regular units beside it.
static func ruler_stat_at(ruler_id: String, stat: String, kept: int, generation: int = 1) -> Dictionary:
	var name := RulerRules.ruler_name(ruler_id, generation)
	if RulerRules.ruler_data(ruler_id).is_empty():
		return _make(stat.capitalize(), "This is not a ruler in this game.", [], stat.capitalize(), 0)
	var stats := RulerRules.ruler_stats(ruler_id, kept, generation)
	if stat == "morale":
		var mdesc := "The morale %s fights with when no regular units stand beside it. While it stands, it also gives its side +%d morale. %s" % [
			name, RulerData.RULER_MORALE, UnitType.describe("morale")]
		return _coded(_make("Morale of %s" % name, mdesc, [_line("Morale of %s" % name, stats.morale, "the same at any kept power")],
			"Morale when it fights alone", stats.morale), "ruler_in_battle")
	var label := String(RulerRules.STAT_NAMES.get(stat, stat))
	var parts := RulerRules.stat_parts(ruler_id, stat, kept)
	var every := ("+%d for every kept power" % parts.gain) if parts.per == 1 \
		else ("+%d for every %d kept power, rounded down" % [parts.gain, parts.per])
	var lines := [_line("Base %s of %s" % [label.to_lower(), name], parts.base, "with no kept power"),
		_line("From %d kept power" % clampi(kept, 0, RulerData.POWER_POOL), parts.from_kept, every)]
	var desc := "%s With 0 kept power %s has %d %s; with all %d kept, %d." % [UnitType.describe(stat), name,
		RulerRules.stat_value(ruler_id, stat, 0), label.to_lower(), RulerData.POWER_POOL,
		RulerRules.stat_value(ruler_id, stat, RulerData.POWER_POOL)]
	return _coded(_make("%s of %s" % [label, name], desc, lines, label, stats[stat]), "ruler_power")


## ruler_stat_at for the faction's current ruler and kept power.
static func ruler_stat(state: GameState, faction_id: String, stat: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return _coded(_make(stat.capitalize(), "This faction has no ruler in this game.", [], stat.capitalize(), 0), "ruler")
	return ruler_stat_at(f.ruler_type, stat, f.kept_power, f.ruler_generation)


## A ruler's ability rank at `kept` power (§7.1): "Ability rank 2 = 1 + 4 kept power / 3 (rounded
## down)", then what that rank does.
static func ability_rank_at(ruler_id: String, kept: int, generation: int = 1) -> Dictionary:
	var name := RulerRules.ruler_name(ruler_id, generation)
	if RulerRules.ruler_data(ruler_id).is_empty():
		return _make("Ability rank", "This is not a ruler in this game.", [], "Ability rank", 0)
	var rank := RulerRules.ability_rank(kept)
	var lines := [_line("Every ruler", 1, "rank 1 with no kept power"),
		_line("From %d kept power" % clampi(kept, 0, RulerData.POWER_POOL), rank - 1,
			"+1 rank for every %d kept power, rounded down, up to rank %d" % [RulerData.ABILITY_RANK_PER, RulerData.MAX_ABILITY_RANK])]
	var desc := "%s at rank %d: %s %s" % [RulerRules.ability_name(ruler_id), rank,
		RulerRules.ability_text(ruler_id, rank, generation), RulesCodex.text("ability_rank")]
	return _coded(_make("Ability rank of %s" % name, desc, lines, "Ability rank", rank), "ability_rank")


## ability_rank_at for the faction's current ruler and kept power.
static func ability_rank(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not f.has_ruler():
		return _coded(_make("Ability rank", "This faction has no ruler in this game.", [], "Ability rank", 0), "ability_rank")
	return ability_rank_at(f.ruler_type, f.kept_power, f.ruler_generation)


## A roster unit's or commander's stat with the faction's mandates (§7.1): "hp" (maximum hit
## points), "attack", "defense" or "cost", e.g. "Defense 6 = Spearmen 5 + Royal Armories 1" or
## "Knights 16 gold = 20 - Muster Grounds 4". From RulerRules.unit_stats.
static func unit_stat(state: GameState, faction_id: String, unit_type_id: String, stat: String) -> Dictionary:
	var us := RulerRules.unit_stats(state, faction_id, unit_type_id)
	var label := String(RulerRules.STAT_NAMES.get(stat, stat))
	if not us.get("ok", false) or not us.base.has(stat):
		return _make(label, "This faction can't recruit that unit type.", [], label, 0)
	var lines := [_line(us.name, us.base[stat], "its own %s" % label.to_lower())]
	var names := []
	for m in us.mods[stat]:
		lines.append(_line(m.name, m.value, "mandate"))
		names.append(m.name)
	var desc := "%s %s" % [UnitType.describe(stat), "No mandate of yours changes it." if names.is_empty()
		else "Your mandates change it: %s." % ", ".join(names)]
	return _coded(_make("%s of %s" % [label, us.name], desc, lines, label, us[stat]), "mandates")


## Sum of the line values. Equal to the breakdown's total by construction; tests check it.
static func sum_of_lines(breakdown: Dictionary) -> int:
	var total := 0
	for l in breakdown.get("lines", []):
		total += int(l.value)
	return total


static func _make(title: String, description: String, lines: Array, total_label: String, total: int) -> Dictionary:
	return {"title": title, "description": description, "lines": lines, "total_label": total_label, "total": total}


static func _line(label: String, value: int, note: String) -> Dictionary:
	return {"label": label, "value": value, "note": note}


## The breakdown with the RulesCodex entry that explains it.
static func _coded(breakdown: Dictionary, codex_key: String) -> Dictionary:
	breakdown["codex"] = codex_key
	return breakdown


static func _faction_name(state: GameState, fid: String) -> String:
	var f := state.find_faction(fid)
	return f.faction_name if f else "an unknown faction"


static func _province_name(state: GameState, pid: String) -> String:
	var p := state.find_province(pid)
	return p.name if p else "a place not on the map"
