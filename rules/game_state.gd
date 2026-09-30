class_name GameState
## Central pure data model. Created from data + seed. Supports deep copy and dict serialization for replays.

var provinces: Array[Province] = []
var factions: Array[Faction] = []
var armies: Array[Army] = []
var rng: SeededRNG
var current_turn: int = 0
var seed_value: int = 0

func _init(map_seed: int = 12345) -> void:
	seed_value = map_seed
	rng = SeededRNG.new(map_seed)
	_load_data()

func _load_data() -> void:
	provinces = MapData.create_provinces()
	factions = FactionData.create_factions()
	
	# Initial armies (one small army per capital for testing)
	for f in factions:
		var capital_province := ""
		for p in provinces:
			if p.is_capital and (p.owner.is_empty() or p.owner == f.id):
				capital_province = p.id
				p.owner = f.id
				break
		
		if not capital_province.is_empty():
			var army := Army.new()
			army.owner = f.id
			army.location = capital_province
			
			# Add one of each unit type
			for ut in f.unit_types:
				army.units.append(Unit.new(ut, f.id))
			
			# Add commander
			if f.commander_type:
				army.commander = Unit.new(f.commander_type, f.id)
			
			armies.append(army)

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
		"seed_value": seed_value,
		"rng": rng.to_dict(),
	}

static func from_dict(data: Dictionary, errors = null) -> GameState:
	var state := GameState.new(data.get("seed_value", 12345))
	state.current_turn = data.get("current_turn", 0)
	
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
	
	return state

func deep_copy(errors = null) -> GameState:
	var copy := GameState.new(seed_value)
	copy.current_turn = current_turn
	copy.provinces.clear()
	for p in provinces:
		copy.provinces.append(Province.from_dict(p.to_dict()))
	copy.factions.clear()
	for f in factions:
		copy.factions.append(Faction.from_dict(f.to_dict()))
	copy.armies.clear()
	var all_unit_types := {}
	for f in copy.factions:
		for ut in f.unit_types:
			all_unit_types[ut.id] = ut
		if f.commander_type:
			all_unit_types[f.commander_type.id] = f.commander_type
	# Build province_ids lookup
	var province_ids := {}
	for p in copy.provinces:
		province_ids[p.id] = true
	for a in armies:
		var army = Army.from_dict(a.to_dict(), all_unit_types, province_ids, errors)
		if army == null:
			return null
		copy.armies.append(army)
	# Copy RNG state for replay fidelity
	copy.rng = SeededRNG.from_dict(rng.to_dict())
	return copy

# Example RNG usage for tests
func roll_for_test() -> int:
	return rng.randi_range(1, 100)
