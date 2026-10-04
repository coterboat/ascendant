class_name Breakdown
## Number breakdowns for tooltips: where every number the UI shows comes from.
## Pure functions over GameState (no Node dependencies). Each returns the same shape:
##   {"title": String, "description": String, "lines": [{"label", "value", "note"}],
##    "total_label": String, "total": int}
## and the total always equals the sum of the line values, so a tooltip can show
## "base + modifiers = total" and never disagree with the number on screen.
## The math is taken from the rules code (TurnResolver.income_of, StubBattleResolver.army_strength),
## never redone here, and the descriptions come from the model describe() strings and RulesCodex.


## Income a province earns its owner each turn: base income plus modifiers. In M1 there are none. With
## rulers (M2), the owner's Heavy Tithes (+1) and Royal Court (the King is here) each get a line, from
## RulerRules.province_income_parts, the same parts the income phase pays (§7.1).
static func province_income(state: GameState, province_id: String) -> Dictionary:
	var p := state.find_province(province_id)
	if p == null:
		return _make("Income", "This place is not on the map.", [], "Income per turn", 0)
	var parts := RulerRules.province_income_parts(state, p.id)
	var lines := [_line("Base income of %s" % p.name, p.income, "set by the map")]
	if parts.mods.is_empty():
		lines.append(_line("Modifiers", 0, "none yet: terrain, forts and capitals do not change income in this milestone"))
	for m in parts.mods:
		lines.append(_line(String(m.name), int(m.value), String(m.note)))
	var owner_text := "Nobody owns it, so nobody earns this gold." if p.owner.is_empty() \
		else "%s earns this gold at the end of each turn." % _faction_name(state, p.owner)
	var desc := "%s %s %s" % [Province.describe("income"), owner_text, RulesCodex.text("income")]
	for m in parts.mods:
		desc += " %s" % _modifier_rule(m.key)
	return _make("Income of %s" % p.name, desc, lines, "Income per turn", int(parts.total))


## A faction's gold now, plus the income of each province it owns, giving its gold next turn
## before any recruits are paid for. Province lines use TurnResolver.income_of (same as the resolver),
## so each one includes Heavy Tithes and Royal Court (M2), named in its note.
static func gold(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _make("Gold", "This faction is not in the game.", [], "Gold next turn", 0)
	var lines := [_line("Gold now", f.gold, "in the treasury")]
	var income: Dictionary = TurnResolver.income_of(state, faction_id)
	var ids: Array = income.by_province.keys()
	ids.sort()
	for pid in ids:
		var parts := RulerRules.province_income_parts(state, pid)
		var note := "a province you own"
		if not parts.mods.is_empty():
			var bits := ["%d base" % int(parts.base)]
			for m in parts.mods:
				bits.append("%s %d" % [m.name, int(m.value)])
			note = " + ".join(bits)
		lines.append(_line("Income from %s" % _province_name(state, pid), income.by_province[pid], note))
	var desc := "%s Gold next turn assumes you recruit nothing and no provinces change hands. %s" % [
		Faction.describe("gold"), RulesCodex.text("income")]
	if not income.modifiers.is_empty():
		desc += " %s" % TurnResolver.income_modifiers_text(state, faction_id, income, "is now")
	return _make("Gold of %s" % f.faction_name, desc, lines, "Gold next turn (before recruits)", f.gold + income.total)


## The one-sentence rule behind an income modifier (RulerRules.province_income_parts' "key").
static func _modifier_rule(key: String) -> String:
	match key:
		RulerRules.HEAVY_TITHES:
			return "Heavy Tithes: every province you own earns %d more gold." % RulerRules.TITHE_GOLD
		RulerRules.ROYAL_COURT:
			return "Royal Court: the province the King is in earns more gold, if you own it, so it follows him when he moves."
		"income_floor":
			return "A province never earns less than nothing."
	if key.begins_with(AscensionRules.PART_PREFIX):
		return AscensionRules.part_rule(key)  # M4: Market Charters, Tithe of Light, Deep Mines, Bounty of the Wild
	return ""


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
		desc += " " + unit_type_description(ut, RulerRules.price_text(state, army.owner, ut))
	return _make(unit_type_name, desc, [_line("%s in this army" % unit_type_name, count, "")], unit_type_name, count)


## Plain description of a unit type's stats, using the UnitType describe() strings. `price` is what its
## faction pays for one, as RulerRules.price_text gives it ("16 gold (20 - Muster Grounds 4)"); without
## it, the type's own cost.
static func unit_type_description(ut: UnitType, price: String = "") -> String:
	return "%s: hit points %d (%s) Attack %d (%s) Defense %d (%s) Morale %d (%s) Recruit cost %s. Trait %s: %s" % [
		ut.name, ut.hp, UnitType.describe("hp"), ut.attack, UnitType.describe("attack"),
		ut.defense, UnitType.describe("defense"), ut.morale, UnitType.describe("morale"),
		price if not price.is_empty() else "%d gold" % ut.cost, ut.trait_id, ut.get_trait_desc()]


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
## "Knights 16 gold = 20 - Muster Grounds 4". From RulerRules.unit_stats. M4: in a game with paths the
## path's parts are lines too ("Max hp 11 = Spearmen 8 + Drillyard 3"), and "morale" is a stat.
static func unit_stat(state: GameState, faction_id: String, unit_type_id: String, stat: String) -> Dictionary:
	var us := RulerRules.unit_stats(state, faction_id, unit_type_id)
	var label := String(RulerRules.STAT_NAMES.get(stat, stat))
	if not us.get("ok", false) or not us.base.has(stat):
		return _make(label, "This faction can't recruit that unit type.", [], label, 0)
	var lines := [_line(us.name, us.base[stat], "its own %s" % label.to_lower())]
	var names := []
	var path_names := []
	for m in us.mods[stat]:
		if m.has("node"):  # M4: a path part
			lines.append(_line(m.name, m.value, String(m.get("note", "path"))))
			path_names.append(m.name)
			continue
		lines.append(_line(m.name, m.value, "mandate"))
		names.append(m.name)
	var desc := "%s %s" % [UnitType.describe(stat), "No mandate of yours changes it." if names.is_empty()
		else "Your mandates change it: %s." % ", ".join(names)]
	if not path_names.is_empty():
		desc += " Your path changes it: %s. %s" % [", ".join(path_names), RulesCodex.text("path_node")]
	return _coded(_make("%s of %s" % [label, us.name], desc, lines, label, us[stat]), "mandates" if path_names.is_empty() else "path_node")


# --- mid-game sacrifice and succession countdown (M2-6, #34) ---------------------------------------

## What a mandate costs by sacrifice (§2.4): "Royal Armories by sacrifice 5 = price 4 + 1 for a
## mid-game sacrifice".
static func sacrifice_cost(mandate_id: String) -> Dictionary:
	var name := RulerRules.mandate_name(mandate_id)
	var lines := [_line("Price of %s" % name, RulerRules.mandate_cost(mandate_id), "what it costs before the game"),
		_line("Mid-game sacrifice", MandateData.SACRIFICE_PREMIUM, "a mandate bought during the game costs more")]
	return _coded(_make("%s by sacrifice" % name, RulesCodex.text("sacrifice"), lines, "Power it costs",
		RulerRules.sacrifice_cost(mandate_id)), "sacrifice")


## The faction's kept power after sacrificing for `mandate_id`: kept power now minus the sacrifice's cost.
static func sacrifice_kept_power(state: GameState, faction_id: String, mandate_id: String) -> Dictionary:
	var kept := RulerRules.kept_power(state, faction_id)
	var cost := RulerRules.sacrifice_cost(mandate_id)
	var name := RulerRules.mandate_name(mandate_id)
	var lines := [_line("Kept power now", kept, RulerRules.current_name(state, faction_id)),
		_line("%s by sacrifice" % name, -cost, "price %d + %d for a mid-game sacrifice" % [RulerRules.mandate_cost(mandate_id),
			MandateData.SACRIFICE_PREMIUM])]
	return _coded(_make("Kept power after the sacrifice", RulesCodex.text("sacrifice"), lines, "Kept power after",
		kept - cost), "sacrifice")


## How the hit points of the faction's regular units on the map change when a sacrifice buys a mandate
## that adds hit points (Veteran Levies, §2.3): their total now, plus what they gain at once.
static func sacrifice_unit_hp(mandate_name: String, hp_before: int, hp_after: int, units: int) -> Dictionary:
	var lines := [_line("Hit points of your regular units now", hp_before, "%d %s on the map" % [units, "unit" if units == 1 else "units"]),
		_line(mandate_name, hp_after - hp_before, "bought by sacrifice, units already on the map gain the hit points at once")]
	return _coded(_make("Hit points of your regular units", "Bought by sacrifice, %s gives the regular units you already have its extra hit points at once, as current and maximum hit points." % mandate_name,
		lines, "Hit points after", hp_after), "sacrifice")


## What `faction_id` earns in this turn's income phase if no provinces change hands: each province it
## owns, with Heavy Tithes and Royal Court in the notes (TurnResolver.income_of, as the phase pays).
## `ruler_at` moves the ruler for a forecast, as income_of takes it.
static func income(state: GameState, faction_id: String, ruler_at: Dictionary = {}) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _make("Income", "This faction is not in the game.", [], "Income this turn", 0)
	var inc := TurnResolver.income_of(state, faction_id, ruler_at)
	var ids: Array = inc.by_province.keys()
	ids.sort()
	var lines := []
	for pid in ids:
		var parts := RulerRules.province_income_parts(state, pid, ruler_at)
		var bits := ["%d base" % int(parts.base)]
		for m in parts.mods:
			bits.append("%s %d" % [m.name, int(m.value)])
		lines.append(_line(_province_name(state, pid), int(inc.by_province[pid]), " + ".join(bits)))
	var desc := "%s This assumes no provinces change hands." % RulesCodex.text("income")
	if not inc.modifiers.is_empty():
		desc += " %s" % TurnResolver.income_modifiers_text(state, faction_id, inc, "ends the turn")
	return _coded(_make("Income of %s this turn" % f.faction_name, desc, lines, "Income this turn", int(inc.total)), "income")


## Turns until a dead ruler's successor arrives (§5.4, "heir in 2 turns"): the turn it arrives at the end
## of, minus the turns before the one being ordered. 0 when it waits for the capital.
static func successor_countdown(state: GameState, faction_id: String) -> Dictionary:
	var info := RulerRules.succession_info(state, faction_id)
	if info.is_empty():
		return _coded(_make("Successor", "This faction's ruler is alive, so no successor is due.", [], "Turns until a successor", 0), "succession")
	var due := int(info.successor_turn)
	var now := state.current_turn + 1
	var who := String(info.heir_name) if String(info.kind) == "mortal" else String(info.successor_name)
	var lines := [_line("Arrives at the end of turn", due, "%s, at %s" % [who, String(info.capital_name)]),
		_line("Turns before this one", -(now - 1), "this is turn %d" % now)]
	var total := RulerRules.successor_countdown(state, faction_id)
	if total == 0:
		lines.append(_line("Waiting for the capital", -(due - now + 1), "a successor arrives only while you hold your capital"))
	var desc := "%s %s" % [RulerRules.successor_sentence(info), RulesCodex.text(String(info.codex))]
	return _coded(_make("Successor of %s" % String(info.name), desc, lines, "Turns until it arrives, this one included", total),
		String(info.codex))


# --- research (M4-1, #66; design/M4_ASCENSION.md §9.2) ---------------------------------------------

## Research per turn (§2.1): "Research 11 a turn = Crownkeep (capital) 5 + 6 other provinces 6", from
## AscensionRules.research_rate, the number the research phase adds.
static func research_rate(state: GameState, faction_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not AscensionRules.has_paths(state):
		return _coded(_make("Research per turn", "This game has no paths, so nobody researches.", [], "Research per turn", 0), "research_points")
	var rate := AscensionRules.research_rate(state, faction_id)
	var lines := []
	for part in rate.parts:
		lines.append(_line(String(part.name), int(part.value), String(part.note)))
	var desc := RulesCodex.text("research_points")
	return _coded(_make("Research per turn of the %s" % f.faction_name, desc, lines, "Research per turn", int(rate.rate)),
		"research_points")


## The research pool after this turn's research phase (§9.2): "Research after this turn 21 = pool now 12
## + this turn 9". The description says what the node (`node_id`, default the faction's target, or the
## target `orders` set) needs: "Arbalests needs 15, so it is done at the end of turn 5 and 6 carry over."
## From Forecast.research, so it matches the forecast and the research phase.
static func research_progress(state: GameState, faction_id: String, orders: Array = [], node_id: String = "") -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not AscensionRules.has_paths(state):
		return _coded(_make("Research", "This game has no paths, so nobody researches.", [], "Research after this turn", 0), "research")
	var fc := Forecast.research(state, faction_id, orders, node_id)
	var pool := AscensionRules.research_points(state, faction_id)
	var gain := int(AscensionRules.research_rate(state, faction_id).rate)
	var lines := [_line("Research saved now", pool, "spare points are never lost"),
		_line("This turn's research", gain, String(AscensionRules.research_rate(state, faction_id).short))]
	var desc := RulesCodex.text("research_phase")
	var target := String(fc.get("target", ""))
	if fc.get("ok", false) and not target.is_empty():
		var name := AscensionRules.node_name(target)
		var cost := int(fc.cost)
		if int(fc.eta) == 1:
			desc = "%s needs %d, so it is done at the end of turn %d and %d carry over. %s" % [name, cost, int(fc.done_turn),
				pool + gain - cost, desc]
		elif int(fc.eta) > 1:
			desc = "%s needs %d, so it is done at the end of turn %d, in %d turns. %s" % [name, cost, int(fc.done_turn),
				int(fc.eta), desc]
		else:
			desc = "%s needs %d, and at this pace it is never done. %s" % [name, cost, desc]
	elif not String(fc.get("reason", "")).is_empty():
		desc = "%s %s" % [String(fc.reason), desc]
	return _coded(_make("Research of the %s" % f.faction_name, desc, lines, "Research after this turn", pool + gain), "research_phase")


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
