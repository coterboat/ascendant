extends RefCounted
## Constructed battles for the M4-3 tests (#68): a game with paths, its armies built by hand, the new
## units put on the field from PathData.NEW_UNITS. Pure: nothing here changes a rule.

const CROWN := "kingdom"
const CLANS := "beasts"


## A game with paths and no armies but the rulers' own (at their capitals: a living ruler always has its
## army). Neither faction owns a mandate unless `mandates` says so ({fid: [ids]}), so every number in its
## battles is the units' and the path's.
static func game(mandates: Dictionary = {}) -> GameState:
	var s := GameState.with_paths(7, {}, [])
	var keep: Array[Army] = []
	for a in s.armies:
		if a.ruler != null:
			keep.append(a)
	s.armies = keep
	# The rulers' armies keep the ids these battles were written with (kingdom-3, beasts-4: from before each
	# faction counted its own armies, #94), so the ids the tests give their own armies never clash with them.
	for i in s.factions.size():
		var ruler := RulerRules.ruler_army(s, s.factions[i].id)
		if ruler != null:
			ruler.id = "%s-%d" % [s.factions[i].id, s.factions.size() + i + 1]
			s.next_army_ids[s.factions[i].id] = s.factions.size() + i + 2
	for f in s.factions:
		f.mandates = mandates.get(f.id, []).duplicate()
	return s


## `s` with `ids` researched by `fid` (AscensionRules.with_nodes: since M4-2 it renames the changed unit and
## puts the new unit on the roster; unit_type() below is then a no-op for it).
static func with_nodes(s: GameState, fid: String, ids: Array) -> GameState:
	var out := AscensionRules.with_nodes(s, fid, ids)
	for nid in ids:
		var new_unit := String(AscensionRules.node_effects(nid).get("new_unit", ""))
		if not new_unit.is_empty():
			unit_type(out, fid, new_unit)
	return out


## The unit type `type_id` of `fid`: its roster's, or a new unit from PathData.NEW_UNITS added to the roster
## (AscensionRules.new_unit_type, with its trait text from AutoBattleResolver.TRAIT_TEXT). Tests use it to
## field a new unit for the other faction too, to try a trait against any roster.
static func unit_type(s: GameState, fid: String, type_id: String) -> UnitType:
	var f := s.find_faction(fid)
	var ut := TurnResolver.recruitable_type(f, type_id)
	if ut != null:
		return ut
	ut = AscensionRules.new_unit_type(type_id)
	f.unit_types.append(ut)
	return ut


## An army of `fid` at `location` made of `type_ids` (unit and commander ids), every unit at its full
## maximum hp (path parts included). Added to the state.
static func army(s: GameState, fid: String, id: String, location: String, type_ids: Array) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = fid
	a.location = location
	var f := s.find_faction(fid)
	for type_id in type_ids:
		if f.commander_type != null and type_id == f.commander_type.id:
			a.commander = Unit.new(f.commander_type, fid)
			continue
		var u := Unit.new(unit_type(s, fid, type_id), fid)
		u.current_hp = RulerRules.unit_max_hp(s, u)
		a.units.append(u)
	s.armies.append(a)
	return a


## Fights one battle with the real resolver, recording its log. `kind` "province" (in `where`, a province
## id, with `defender` holding it, or "" when both arrived) or "border" (`where` is "a|b").
static func fight(s: GameState, armies: Array, where: String, defender: String, seed_value: int, kind := "province") -> Dictionary:
	var by_faction := {}
	for a in armies:
		if not by_faction.has(a.owner):
			by_faction[a.owner] = []
		by_faction[a.owner].append(a)
	var fids: Array = by_faction.keys()
	fids.sort()
	var sides := []
	for fid in fids:
		sides.append({"faction": fid, "armies": by_faction[fid]})
	var pids: Array = Array(where.split("|")) if kind == "border" else [where]
	var ctx := {"kind": kind, "defender": defender, "province": s.find_province(pids[0]) if kind == "province" else null,
		"province_ids": pids, "state": s}
	return AutoBattleResolver.fight(sides, ctx, SeededRNG.new(seed_value), true)


## The log's fighter ids of `type_id` (by its log "type").
static func fighters_of(battle_log: Dictionary, type_id: String) -> Array:
	var out := []
	for f in battle_log.fighters:
		if f.type == type_id:
			out.append(int(f.id))
	return out
