extends RefCounted
## Shared set-ups for the forts and sieges tests (M3c S-1a, #98): states with sieges on and chosen armies, forts and
## owners. Not a test file itself (the runner only runs test_*.gd).

const CROWN := "kingdom"
const CLANS := "beasts"


## A game with sieges (forts at their starting levels and full walls) whose starting armies are replaced by
## `specs`: [[id, owner, location, [unit type ids], engines (optional)], ...]. `owners` sets province owners.
static func state(specs: Array, owners: Dictionary = {}, seed_value: int = 99) -> GameState:
	var s := GameState.with_sieges(seed_value)
	s.armies.clear()
	for spec in specs:
		s.armies.append(army(s, spec))
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


static func army(s: GameState, spec: Array) -> Army:
	var a := Army.new()
	a.id = spec[0]
	a.owner = spec[1]
	a.location = spec[2]
	var f := s.find_faction(a.owner)
	for type_id in spec[3]:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			a.commander = Unit.new(ut, f.id)
		else:
			a.units.append(Unit.new(ut, f.id))
	if spec.size() > 4:
		a.engines = int(spec[4])
	return a


## `n` units of `type_id`.
static func units(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


## Makes `province_id` a fort of `level` at `walls` (full when -1).
static func set_fort(s: GameState, province_id: String, level: int, walls: int = -1) -> void:
	var p := s.find_province(province_id)
	p.fort_level = level
	p.has_fort = level > 0
	p.walls = SiegeRules.walls_max(level) if walls < 0 else walls


## Resolves one turn (StubBattleResolver unless `real` battles are asked for).
static func resolve(s: GameState, orders: Dictionary, real: bool = false, turn_seed: int = 7) -> Dictionary:
	return TurnResolver.resolve(s, orders, turn_seed, AutoBattleResolver.new() if real else StubBattleResolver.new())


static func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)


## A faction's gold, set high so a test is about the rule, not the treasury.
static func rich(s: GameState, fid: String, gold: int = 1000) -> void:
	s.find_faction(fid).gold = gold
