class_name GameState
## Central pure data model. Created from data + seed. Supports deep copy and dict serialization for replays.
## to_dict() survives a JSON round-trip exactly: 64-bit values (seed, RNG state) are stored as strings
## and every number is read back as an int on load (see Serial). from_dict() validates owners,
## neighbors and capitals and fails with a plain-language error.
##
## Rulers (M2, #29) are opt-in at setup until battles and succession handle them (director's note on
## #29): GameState.new(seed) is exactly the M1 game, and GameState.with_rulers(seed, builds) is the M1
## game plus a ruler, kept power and mandates for every faction, with each ruler's army at its capital.

var provinces: Array[Province] = []
var factions: Array[Faction] = []
var armies: Array[Army] = []
var rng: SeededRNG
var current_turn: int = 0
var seed_value: int = 0
var next_army_id: int = 1  # counter behind new_army_id(); serialized so replays hand out the same ids

func _init(map_seed: int = 12345) -> void:
	seed_value = map_seed
	rng = SeededRNG.new(map_seed)
	_load_data()

func _load_data() -> void:
	provinces = MapData.create_provinces()
	factions = FactionData.create_factions()
	place_starting_armies()
	validate()

## Gives each faction the province named by its `capital` field (never map order) and one starting
## army there with one of each unit type and its commander. Returns false if a capital is missing.
func place_starting_armies(errors = null) -> bool:
	armies.clear()
	next_army_id = 1
	var ok := true
	for f in factions:
		var capital := find_province(f.capital)
		if capital == null:
			_report(errors, "The capital of %s, '%s', is not a province on this map." % [f.faction_name, f.capital])
			ok = false
			continue
		capital.owner = f.id
		var army := Army.new()
		army.id = new_army_id(f.id)
		army.owner = f.id
		army.location = capital.id
		for ut in f.unit_types:
			army.units.append(Unit.new(ut, f.id))
		if f.commander_type:
			army.commander = Unit.new(f.commander_type, f.id)
		armies.append(army)
	return ok

## The M1 starting state plus a ruler for every faction (design/M2_RULER.md §1.5). `builds` maps a
## faction id to its build, {"ruler": ruler id, "mandates": [mandate ids]}, or to a preset id
## (BuildPresetData); a faction with no build gets its balanced preset. Returns null when a build is
## illegal, with the plain-language reasons appended to `errors` (or push_error when it isn't an Array).
static func with_rulers(map_seed: int = 12345, builds: Dictionary = {}, errors = null) -> GameState:
	var state := GameState.new(map_seed)
	if not state.setup_rulers(builds, errors):
		return null
	return state


## Gives every faction its ruler and mandates before turn 1 (see with_rulers). All or nothing: if any
## build is illegal, nothing changes and the reasons go to `errors`. Each ruler's army is placed at its
## capital after every starting army (army 1 there, the ruler's army 2), in faction order, so the M1
## starting armies keep their ids: kingdom-1, beasts-2, then kingdom-3 and beasts-4 for the rulers.
func setup_rulers(builds: Dictionary = {}, errors = null) -> bool:
	var problems := []
	for key in builds:
		if find_faction(str(key)) == null:
			problems.append("A build was given for a faction that is not in this game.")
	if current_turn != 0:
		problems.append("Rulers and their builds are chosen before the game starts.")
	var chosen := {}
	for f in factions:
		chosen[f.id] = builds.get(f.id, RulerRules.balanced_preset(f.id))
		problems.append_array(RulerRules.build_errors(f.id, chosen[f.id]))
	if problems.is_empty():
		for f in factions:
			problems.append_array(RulerRules.apply_build(self, f.id, chosen[f.id]))
	for msg in problems:
		_report(errors, msg)
	return problems.is_empty() and validate(errors)


## Hands out the next unique army id, e.g. "kingdom-3", skipping ids already in use.
func new_army_id(faction_id: String) -> String:
	var id := "%s-%d" % [faction_id, next_army_id]
	next_army_id += 1
	while find_army(id) != null:
		id = "%s-%d" % [faction_id, next_army_id]
		next_army_id += 1
	return id

func find_province(id: String) -> Province:
	for p in provinces:
		if p.id == id:
			return p
	return null

func find_faction(id: String) -> Faction:
	for f in factions:
		if f.id == id:
			return f
	return null

func find_army(id: String) -> Army:
	for a in armies:
		if a.id == id:
			return a
	return null

## Checks the state is internally consistent: every owner is a real faction, neighbors exist and
## list each other back, every faction's capital is a capital province, army ids are unique.
## Appends plain-language messages to `errors` (or push_error when it isn't an Array).
func validate(errors = null) -> bool:
	var ok := true
	var province_by_id := {}
	for p in provinces:
		if province_by_id.has(p.id):
			_report(errors, "Two provinces share the id '%s'." % p.id)
			ok = false
		province_by_id[p.id] = p
	var faction_by_id := {}
	for f in factions:
		faction_by_id[f.id] = f

	for p in provinces:
		if not p.owner.is_empty() and not faction_by_id.has(p.owner):
			_report(errors, "Province '%s' is owned by '%s', which is not a faction in this game." % [p.id, p.owner])
			ok = false
		for n in p.neighbors:
			if n == p.id:
				_report(errors, "Province '%s' lists itself as a neighbor." % p.id)
				ok = false
			elif not province_by_id.has(n):
				_report(errors, "Province '%s' lists neighbor '%s', which is not a province on this map." % [p.id, n])
				ok = false
			elif not province_by_id[n].neighbors.has(p.id):
				_report(errors, "Province '%s' lists '%s' as a neighbor, but '%s' does not list '%s' back." % [p.id, n, n, p.id])
				ok = false

	var capital_taken_by := {}
	for f in factions:
		if f.capital.is_empty():
			_report(errors, "Faction '%s' has no capital." % f.id)
			ok = false
		elif not province_by_id.has(f.capital):
			_report(errors, "Faction '%s' has capital '%s', which is not a province on this map." % [f.id, f.capital])
			ok = false
		elif not province_by_id[f.capital].is_capital:
			_report(errors, "Faction '%s' has capital '%s', but that province is not marked as a capital." % [f.id, f.capital])
			ok = false
		elif capital_taken_by.has(f.capital):
			_report(errors, "Factions '%s' and '%s' both have capital '%s'." % [capital_taken_by[f.capital], f.id, f.capital])
			ok = false
		else:
			capital_taken_by[f.capital] = f.id

	var army_ids := {}
	for a in armies:
		if a.id.is_empty():
			_report(errors, "An army at '%s' has no id." % a.location)
			ok = false
		elif army_ids.has(a.id):
			_report(errors, "Two armies share the id '%s'." % a.id)
			ok = false
		army_ids[a.id] = true
		if not faction_by_id.has(a.owner):
			_report(errors, "Army '%s' belongs to '%s', which is not a faction in this game." % [a.id, a.owner])
			ok = false
	# Rulers, kept power, mandates and ruler armies (M2): RulerRules owns those rules.
	if not RulerRules.validate(self, errors):
		ok = false
	return ok

func to_dict() -> Dictionary:
	var province_dicts := []
	for p in provinces:
		province_dicts.append(p.to_dict())

	var faction_dicts := []
	for f in factions:
		faction_dicts.append(f.to_dict())

	var army_dicts := []
	for a in armies:
		army_dicts.append(a.to_dict())

	return {
		"provinces": province_dicts,
		"factions": faction_dicts,
		"armies": army_dicts,
		"current_turn": current_turn,
		"seed_value": Serial.int64_to_str(seed_value),
		"next_army_id": next_army_id,
		"rng": rng.to_dict(),
	}

static func from_dict(data: Dictionary, errors = null) -> GameState:
	var state := GameState.new(Serial.to_int(data.get("seed_value", 12345), 12345))
	state.current_turn = Serial.to_int(data.get("current_turn", 0))
	state.next_army_id = Serial.to_int(data.get("next_army_id", 1), 1)

	if data.has("rng"):
		state.rng = SeededRNG.from_dict(data.rng)

	# Rebuild from dict overriding loaded data (for full roundtrip)
	state.provinces.clear()
	for p_data in data.get("provinces", []):
		state.provinces.append(Province.from_dict(p_data))

	state.factions.clear()
	for f_data in data.get("factions", []):
		state.factions.append(Faction.from_dict(f_data))

	# Build lookup for units
	var all_unit_types := {}
	for f in state.factions:
		for ut in f.unit_types:
			all_unit_types[ut.id] = ut
		if f.commander_type:
			all_unit_types[f.commander_type.id] = f.commander_type
	# A ruler's stats are not saved: they are rebuilt from its ruler and kept power (RulerRules).
	for f in state.factions:
		if not f.has_ruler():
			continue
		if RulerRules.ruler_data(f.ruler_type).is_empty():
			_report(errors, "%s is led by '%s', which is not a ruler in this game." % [
				f.faction_name if not f.faction_name.is_empty() else "A faction", f.ruler_type])
			return null
		RulerRules.refresh_ruler_type(f)
		all_unit_types[f.ruler_unit_type.id] = f.ruler_unit_type
	if not RulerRules.validate_factions(state, errors):
		return null

	# Build province_ids lookup
	var province_ids := {}
	for p in state.provinces:
		province_ids[p.id] = true

	state.armies.clear()
	for a_data in data.get("armies", []):
		var army = Army.from_dict(a_data, all_unit_types, province_ids, errors)
		if army == null:
			return null
		state.armies.append(army)

	if not state.validate(errors):
		return null
	return state

## Independent copy with the same RNG state. Goes through to_dict/from_dict so a copy is exactly
## what a save and reload would give.
func deep_copy(errors = null) -> GameState:
	return GameState.from_dict(to_dict(), errors)

# Example RNG usage for tests
func roll_for_test() -> int:
	return rng.randi_range(1, 100)

static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
