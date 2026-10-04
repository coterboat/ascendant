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
##
## Magic and fog of war (M5, design/M5_MAGIC_FOG.md §14; the fields came first, in the M5-0 scaffold, #111) are
## opt-in too, and each of their keys is saved only when set: `fog`, `magic` (with `enchantments` and the factions'
## magic fields), and `is_view` with the stand-ins' view notes (Army.seen) in a player's view. Without them a game
## saves byte-identically to before. Rules: MagicRules (validate checks the magic fields against `magic`); a view
## note only in a view (_validate_views). The per-faction army numbers M5 asks for are next_army_ids (#94).
## M5-1: setup_fog() turns fog on for any game before turn 1; a view (FogRules.view_state) also saves `view_of`, its
## viewer, and validate relaxes four checks for the view's rivals (view_relaxes).

var provinces: Array[Province] = []
var factions: Array[Faction] = []
var armies: Array[Army] = []
var rng: SeededRNG
var current_turn: int = 0
var seed_value: int = 0
## Behind new_army_id(): {faction id: the number its next army gets}. Each faction counts its own armies (#94),
## kingdom-1, kingdom-2, beasts-1, ... in the order it raises them, and a number is never handed out twice.
## Saved, so a loaded game and a replay hand out the same ids; a save from before it takes each faction's next
## number from its highest army id (from_dict).
var next_army_ids: Dictionary = {}
var paths: bool = false  # M4: every faction has a path and researches (AscensionRules); saved only when true
var sieges: bool = false  # M3c: forts have levels and walls, and armies besiege them (SiegeRules); saved only when true
# --- M5, magic and fog of war (design/M5_MAGIC_FOG.md §14) ---
var fog: bool = false  # fog of war: a lens on what each player is shown, never a rule (§2.1); saved only when true
var magic: bool = false  # spells, rituals and enchantments (MagicRules); needs paths; saved only when true
## The enchantments in play (§6.4), kept sorted by id: {"id", "ritual", "faction", "kind", "province", "armies",
## "cast_turn", "until_turn", "bonus", "ending"} each (MagicRules.ENCHANTMENT_KEYS). Saved only in a magic game.
var enchantments: Array = []
var is_view: bool = false  # one player's view of the game (FogRules, §2.7), never the true state; saved only when true
## Whose view it is (M5-1, FogRules.view_state): the viewer's faction id, saved with is_view. validate relaxes four
## checks for the other factions of a view, its rivals (view_relaxes); "" in a true state.
var view_of: String = ""

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
	next_army_ids = {}
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
## starting armies keep their ids: kingdom-1, beasts-1, then kingdom-2 and beasts-2 for the rulers.
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


## Fog of war for any game (M5-1, design/M5_MAGIC_FOG.md §1.3, §2.1): it can follow any setup, before turn 1. Fog is
## a lens, not a rule: the resolver never reads it, so a fog game resolves exactly as the same game without it, and
## only what each player is shown changes (FogRules). The per-faction army numbers fog needs are every game's rule
## since #94 (next_army_ids), so there is no counter to set up (§2.1's director's note). Returns false, with a plain
## reason in `errors`, when it is too late.
func setup_fog(errors = null) -> bool:
	if current_turn != 0:
		_report(errors, "Fog of war is chosen before the game starts.")
		return false
	fog = true
	return validate(errors)


## True when `faction_id` is a rival in a player's view (M5-1, §2.7): validate relaxes exactly four checks for it,
## because a view holds only what its viewer knows of a rival: AscensionRules.validate's prerequisites and order of
## `researched`, RulerRules.validate_factions' kept-power arithmetic and sacrifice-only check, _living_rulers_on_map,
## and summoned units' `until` (stand-ins carry 0; MagicRules). Never in a true state, and never for the viewer.
func view_relaxes(faction_id: String) -> bool:
	return is_view and faction_id != view_of


## Hands out `faction_id`'s next army id, e.g. "kingdom-3": its own count (next_army_ids), skipping ids
## already in use.
func new_army_id(faction_id: String) -> String:
	var n := int(next_army_ids.get(faction_id, 1))
	var id := "%s-%d" % [faction_id, n]
	n += 1
	while find_army(id) != null:
		id = "%s-%d" % [faction_id, n]
		n += 1
	next_army_ids[faction_id] = n
	return id


## For a save from before next_army_ids: each faction's next number, one past the highest number among its
## armies' ids ("kingdom-7" -> 8), or 1 when it has none.
func _next_ids_from_armies() -> Dictionary:
	var out := {}
	for f in factions:
		out[f.id] = 1
	for a in armies:
		var prefix := a.owner + "-"
		if not a.id.begins_with(prefix):
			continue
		var digits := a.id.substr(prefix.length())
		if digits.is_valid_int():
			out[a.owner] = maxi(int(out.get(a.owner, 1)), digits.to_int() + 1)
	return out

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
	# Magic (M5): MagicRules owns those rules; a game without magic carries none of its fields.
	if not MagicRules.validate(self, errors):
		ok = false
	if not _validate_views(errors):
		ok = false
	return ok


## M5 (§2.7): a view note (Army.seen) belongs only to a stand-in in a player's view, and has its fixed shape there
## (Army.validate_seen). A true state never has one.
func _validate_views(errors) -> bool:
	var ok := true
	if not view_of.is_empty() and (not is_view or find_faction(view_of) == null):
		_report(errors, "This game says it is the view of '%s', but %s." % [view_of,
			"it is the true game, not a player's view" if not is_view else "that is not a faction in this game"])
		ok = false
	for a in armies:
		if a.seen.is_empty():
			continue
		if not is_view:
			_report(errors, "Army '%s' carries a view note, but this is the true game, not a player's view of it. Only a view's stand-ins carry notes." % a.id)
			ok = false
		elif not a.validate_seen(errors):
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
		if view_relaxes(f.id):
			continue  # M5-1 (§2.7): a view may know a rival's ruler lives without knowing where (RulerRules.ruler_alive)
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
		faction_dicts.append(f.to_dict(paths, magic))

	var army_dicts := []
	for a in armies:
		army_dicts.append(a.to_dict())

	var next_ids := {}  # #94: each faction's army count, in faction order
	for f in factions:
		next_ids[f.id] = int(next_army_ids.get(f.id, 1))

	var d := {
		"provinces": province_dicts,
		"factions": faction_dicts,
		"armies": army_dicts,
		"current_turn": current_turn,
		"seed_value": Serial.int64_to_str(seed_value),
		"next_army_ids": next_ids,
		"rng": rng.to_dict(),
	}
	if paths:
		d["paths"] = true  # only a game with paths carries the key, so M1 and M2 save exactly as before
	if sieges:
		d["sieges"] = true  # M3c: only a game with sieges carries the key
	if fog:
		d["fog"] = true  # M5: only a game with fog of war carries the key
	if magic:
		d["magic"] = true  # M5: only a game with magic carries the key, its enchantments and its factions' magic fields
		var enchantment_dicts := []
		for e in enchantments:
			enchantment_dicts.append(MagicRules.enchantment_copy(e))
		d["enchantments"] = enchantment_dicts
	if is_view:
		d["is_view"] = true  # M5: only a player's view carries the key
		d["view_of"] = view_of  # M5-1: whose view it is
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
	var next_ids = Serial.expect(data, "next_army_ids", TYPE_DICTIONARY, errors, WHO, {})
	if next_ids == null:
		return null
	var paths_flag = Serial.expect(data, "paths", TYPE_BOOL, errors, WHO, false)
	if paths_flag == null:
		return null
	state.paths = paths_flag
	var sieges_flag = Serial.expect(data, "sieges", TYPE_BOOL, errors, WHO, false)
	if sieges_flag == null:
		return null
	state.sieges = sieges_flag
	for key in ["fog", "magic", "is_view"]:  # M5: present only when set
		var flag = Serial.expect(data, key, TYPE_BOOL, errors, WHO, false)
		if flag == null:
			return null
		state.set(key, flag)
	var viewer = Serial.expect(data, "view_of", TYPE_STRING, errors, WHO, "")  # M5-1: views only
	if viewer == null:
		return null
	state.view_of = String(viewer)
	var enchantment_list = Serial.expect_dicts(data, "enchantments", errors, WHO, "enchantment")  # M5: magic games only
	if enchantment_list == null:
		return null
	for i in enchantment_list.size():
		var e = MagicRules.enchantment_from_dict(enchantment_list[i], errors, Serial.label("enchantment", enchantment_list[i], i))
		if e == null:
			return null
		state.enchantments.append(e)

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

	# #94: each faction's army count; a save from before it goes on from the faction's highest army id.
	state.next_army_ids = state._next_ids_from_armies()
	for fid in next_ids:
		if state.find_faction(str(fid)) != null:
			state.next_army_ids[str(fid)] = Serial.to_int(next_ids[fid], 1)
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
