class_name GameState
## Central pure data model. Created from data + seed. Supports deep copy and dict serialization for replays.
## to_dict() survives a JSON round-trip exactly: 64-bit values (seed, RNG state) are stored as strings
## and every number is read back as an int on load (see Serial). from_dict() validates owners,
## neighbors and capitals and fails with a plain-language error.
##
## Rulers (M2, #29) are opt-in at setup until battles and succession handle them (director's note on
## #29): GameState.new(seed) is exactly the M1 game, and GameState.with_rulers(seed, builds) is the M1
## game plus a ruler, kept power and mandates for every faction, with each ruler's army at its capital.
##
## Paths (M4, #66; design/M4_ASCENSION.md §1.3) are opt-in too: GameState.with_paths(seed, builds) is the
## rulers game plus a path for every faction (`paths` true, research fields on each Faction). Without them
## no path field is saved, so M1 and M2 games, records and saves are byte-identical to before.
##
## Forts and sieges (M3c, design/M3C_SIEGES.md §1.3) are opt-in too, for any game: setup_sieges() before turn
## 1, or GameState.with_sieges(seed, builds, flags). Each fort gets its level and full walls, `sieges` turns
## true, and from then on provinces save their fort and siege fields and armies their engines. Without it
## nothing of that is saved, so M1, M2 and M4 games stay byte-identical. Rules: SiegeRules.

var provinces: Array[Province] = []
var factions: Array[Faction] = []
var armies: Array[Army] = []
var rng: SeededRNG
var current_turn: int = 0
var seed_value: int = 0
var next_army_id: int = 1  # counter behind new_army_id(); serialized so replays hand out the same ids
var paths: bool = false  # M4: every faction has a path and researches (AscensionRules); saved only when true
var sieges: bool = false  # M3c: forts have levels and walls, and armies besiege them (SiegeRules); saved only when true

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


## The rulers game (with_rulers) plus a path for every faction (M4, design/M4_ASCENSION.md §1.3): research
## starts at 0 with no target. Paths need rulers, so this always sets rulers up first. Returns null when a
## build is illegal, with the reasons in `errors`, as with_rulers does.
static func with_paths(map_seed: int = 12345, builds: Dictionary = {}, errors = null) -> GameState:
	var state := with_rulers(map_seed, builds, errors)
	if state == null or not state.setup_paths(errors):
		return null
	return state


## Turns paths on before turn 1 for a game whose factions all have rulers (setup_rulers first): every
## faction gets its path from PathData with an empty pool, no target and nothing researched. Returns false,
## with plain reasons in `errors`, when it is too late or a faction has no ruler or no path.
func setup_paths(errors = null) -> bool:
	var problems := []
	if current_turn != 0:
		problems.append("Paths are chosen before the game starts.")
	for f in factions:
		if not f.has_ruler():
			problems.append("Paths need rulers, and %s has none. Set up rulers first." % f.faction_name)
		if AscensionRules.path_data(f.id).is_empty():
			problems.append("%s has no path in this game." % f.faction_name)
	for msg in problems:
		_report(errors, msg)
	if not problems.is_empty():
		return false
	paths = true
	for f in factions:
		f.research_points = 0
		f.research_target = ""
		f.researched = []
		f.path_branch = ""
	return validate(errors)


## Forts and sieges for any game (M3c, §1.3): the M1 game, with rulers when `flags` has "rulers" (or a
## build in `builds`), with paths when it has "paths" (paths imply rulers), then setup_sieges(). The new
## game screen and the autoplay use it. Returns null when a build is illegal, with the reasons in `errors`.
static func with_sieges(map_seed: int = 12345, builds: Dictionary = {}, flags: Dictionary = {}, errors = null) -> GameState:
	var state: GameState
	if flags.get("paths", false):
		state = with_paths(map_seed, builds, errors)
	elif flags.get("rulers", false) or not builds.is_empty():
		state = with_rulers(map_seed, builds, errors)
	else:
		state = GameState.new(map_seed)
	if state == null or not state.setup_sieges(errors):
		return null
	return state


## Turns forts and sieges on before turn 1 (§1.3): every capital becomes a citadel and every other
## province with a fort on the map a keep (FortData.START), all at full walls. Rosters don't change:
## the siege engines live in FortData, and TurnResolver.recruitable_type offers them only in a game with
## sieges. Returns false, with plain reasons in `errors`, when it is too late.
func setup_sieges(errors = null) -> bool:
	if current_turn != 0:
		_report(errors, "Forts and sieges are chosen before the game starts.")
		return false
	sieges = true
	for p in provinces:
		var level := 0
		if p.is_capital:
			level = int(FortData.START.capital)
		elif p.has_fort:
			level = int(FortData.START.fort)
		p.fort_level = level
		p.has_fort = level > 0
		p.walls = int(FortData.level(level).walls)
		p.fort_by = ""
		p.works = {}
		p.siege_since = 0
		p.owned_since = 0
		p.lost = {}
	return validate(errors)


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
## list each other back, every faction's capital is a capital province, army ids are unique, and (M2)
## the ruler rules hold, including that a living ruler is on the map in its own army.
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
	# Research and paths (M4): AscensionRules owns those rules.
	if not AscensionRules.validate(self, errors):
		ok = false
	# Forts, walls, construction, sieges and engines (M3c): SiegeRules owns those rules.
	if not SiegeRules.validate(self, errors):
		ok = false
	if not _living_rulers_on_map(errors):
		ok = false
	return ok


## A living ruler always travels as its own army (#49): a ruler whose army is gone is dead, and
## TurnResolver records that death right after the battle that removed the army (M2-3), so no state the
## game makes has a living ruler off the map. (Unknown rulers and bad statuses are RulerRules.validate's.)
func _living_rulers_on_map(errors) -> bool:
	var ok := true
	for f in factions:
		if not f.has_ruler() or f.ruler_status != RulerRules.ALIVE or RulerRules.ruler_data(f.ruler_type).is_empty():
			continue
		if RulerRules.ruler_army(self, f.id) == null:
			_report(errors, "%s (%s) is alive but has no ruler's army on the map. A living ruler always travels as its own army, and a ruler whose army is gone is dead." % [
				Serial.cap(RulerRules.current_name(self, f.id)), f.faction_name if not f.faction_name.is_empty() else f.id])
			ok = false
	return ok

func to_dict() -> Dictionary:
	var province_dicts := []
	for p in provinces:
		province_dicts.append(p.to_dict(sieges))

	var faction_dicts := []
	for f in factions:
		faction_dicts.append(f.to_dict(paths))

	var army_dicts := []
	for a in armies:
		army_dicts.append(a.to_dict())

	var d := {
		"provinces": province_dicts,
		"factions": faction_dicts,
		"armies": army_dicts,
		"current_turn": current_turn,
		"seed_value": Serial.int64_to_str(seed_value),
		"next_army_id": next_army_id,
		"rng": rng.to_dict(),
	}
	if paths:
		d["paths"] = true  # only a game with paths carries the key, so M1 and M2 save exactly as before
	if sieges:
		d["sieges"] = true  # M3c: only a game with sieges carries the key
	return d

## Rebuilds a state from to_dict() output (or the same data after a JSON round-trip). Returns null when
## the data is not a valid game, with plain-language reasons in `errors` (or push_error when it isn't
## an Array): a field of the wrong type (#49, Serial load checks: "The 'owner' field of province
## 'westwatch' should be text, but the saved data has a number there."), an unknown ruler, unit type or
## province, or anything validate() rejects. Malformed data never raises a script error.
static func from_dict(data, errors = null) -> GameState:
	const WHO := "the saved game"
	if not Serial.check(data, TYPE_DICTIONARY, errors, WHO):
		return null
	var state := GameState.new(Serial.to_int(data.get("seed_value", 12345), 12345))
	state.current_turn = Serial.to_int(data.get("current_turn", 0))
	state.next_army_id = Serial.to_int(data.get("next_army_id", 1), 1)
	var paths_flag = Serial.expect(data, "paths", TYPE_BOOL, errors, WHO, false)
	if paths_flag == null:
		return null
	state.paths = paths_flag
	var sieges_flag = Serial.expect(data, "sieges", TYPE_BOOL, errors, WHO, false)
	if sieges_flag == null:
		return null
	state.sieges = sieges_flag

	var rng_data = Serial.expect(data, "rng", TYPE_DICTIONARY, errors, WHO, {})
	if rng_data == null:
		return null
	if data.get("rng") != null:
		state.rng = SeededRNG.from_dict(rng_data)

	# Rebuild from dict overriding loaded data (for full roundtrip)
	var province_list = Serial.expect_dicts(data, "provinces", errors, WHO, "province")
	if province_list == null:
		return null
	state.provinces.clear()
	for i in province_list.size():
		var p := Province.from_dict(province_list[i], errors, Serial.label("province", province_list[i], i))
		if p == null:
			return null
		state.provinces.append(p)

	var faction_list = Serial.expect_dicts(data, "factions", errors, WHO, "faction")
	if faction_list == null:
		return null
	state.factions.clear()
	for i in faction_list.size():
		var f := Faction.from_dict(faction_list[i], errors, Serial.label("faction", faction_list[i], i))
		if f == null:
			return null
		state.factions.append(f)

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

	var army_list = Serial.expect_dicts(data, "armies", errors, WHO, "army")
	if army_list == null:
		return null
	state.armies.clear()
	for i in army_list.size():
		var army := Army.from_dict(army_list[i], all_unit_types, province_ids, errors, Serial.label("army", army_list[i], i))
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
