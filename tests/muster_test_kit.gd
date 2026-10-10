extends RefCounted
## ARM-1: shared fixtures for the muster tests (tests/test_muster_*.gd). Not a test file itself (no "test_" prefix).
##
##   game(kind)                       "m1" | "rulers" | "paths" | "sieges" | "magic" | "magic_sieges" | "fog": a seeded game
##   army(s, fid, at, types, cmd, n)  a new army of `fid` at `at` holding `types` (unit type ids), a commander type id
##                                    ("" for none) and `n` engines, appended to `s` with the next real id
##   crown(s)                         the Crown's starting army (kingdom-1, Crownkeep: spearmen, crossbowmen, knights, captain)
##   types(a)                         an army's unit type ids, in order
##   resolve(s, orders)               TurnResolver.resolve with the stub battle resolver (nothing fights unless asked)
##   events(r, type)                  the events of that type in a resolve() result
##   bless(s, fid, army)              a Dawn Blessing on the army, as a cast would leave it: returns the enchantment id

const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 7


static func game(kind: String = "m1") -> GameState:
	var builds := {CROWN: "regents_court", CLANS: "blood_of_the_fang"}
	var s: GameState
	match kind:
		"rulers":
			s = GameState.with_rulers(SEED)
		"paths":
			s = GameState.with_paths(SEED)
		"sieges":
			s = GameState.with_sieges(SEED, {}, {"rulers": true})
		"magic":
			s = GameState.with_magic(SEED, builds)
		"magic_sieges":
			s = GameState.with_magic(SEED, builds)
			s.setup_sieges()
		"fog":
			s = GameState.with_magic(SEED, builds)
			s.setup_fog([])
		_:
			s = GameState.new(SEED)
	assert(s != null)
	return s


static func army(s: GameState, fid: String, at: String, types: Array, commander: String = "", engines: int = 0) -> Army:
	var f := s.find_faction(fid)
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for t in types:
		var ut := TurnResolver.recruitable_type(f, String(t), s)
		assert(ut != null)
		a.units.append(Unit.new(ut, fid))
	if not commander.is_empty():
		a.commander = Unit.new(f.commander_type, fid)
	a.engines = engines
	s.armies.append(a)
	return a


static func crown(s: GameState) -> Army:
	return s.find_army("kingdom-1")


static func clans(s: GameState) -> Army:
	return s.find_army("beasts-1")


static func types(a: Army) -> Array:
	return a.units.map(func(u): return u.type.id)


static func resolve(s: GameState, orders: Dictionary, resolver: BattleResolver = null) -> Dictionary:
	return TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s), resolver if resolver != null else StubBattleResolver.new())


static func events(r: Dictionary, type: String) -> Array:
	return r.events.filter(func(e): return String(e.type) == type)


## A Dawn Blessing on `army` (and every other army of its faction in its province), as a cast leaves it. Returns its id.
static func bless(s: GameState, fid: String, at: String, until: int = 6) -> String:
	var ids := []
	for a in s.armies:
		if a.owner == fid and a.location == at:
			ids.append(a.id)
	ids.sort()
	return String(MagicRules._begin(s, fid, "dawn_blessing", "blessing", at, 1, until, 0, ids).id)
