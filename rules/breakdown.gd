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


## An army's battle strength under the current battle rules: attack + defense of every unit and
## its commander. The total is StubBattleResolver.army_strength, the number battles actually use.
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
	return _make("Strength of the %s" % TurnResolver.army_label(state, army), RulesCodex.text("battle_stub"),
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


## The turn number. Turns count up from 0; each resolved turn adds one (TurnResolver.resolve).
static func turn(state: GameState) -> Dictionary:
	return _make("Turn %d" % state.current_turn,
		"The number of turns resolved so far. %s" % RulesCodex.text("phase_order"),
		[_line("Turns resolved so far", state.current_turn, "")], "Current turn", state.current_turn)


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


static func _faction_name(state: GameState, fid: String) -> String:
	var f := state.find_faction(fid)
	return f.faction_name if f else "an unknown faction"


static func _province_name(state: GameState, pid: String) -> String:
	var p := state.find_province(pid)
	return p.name if p else "a place not on the map"
