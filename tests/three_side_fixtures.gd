extends RefCounted
## Three-sided battles for the battle views' tests, shots and the 3D launcher (#265): a Free Holds garrison caught
## between the Crown and the Clans, each fought with the real AutoBattleResolver through TurnResolver from a constructed
## turn, so every log is a battle event exactly as a game makes it. Each is {"log", "report", "event", "state" (the game
## after the turn), "seats" (the seat order the views colour the sides by), "province", "seed"}. Built once per run and
## cached; each is fought on the first turn seed that shows what it is for (every side fights, and the first side out lasts
## past round 1), so it follows the rules as they are. Not a test file itself (the runner only runs test_*.gd).
##   holds   Rivermarch (plains, a rich hold with a Hold Captain): the Crown marches in from Crownkeep, the Clans from
##           Greenglade, in a game without sieges: a province battle, the Free Holds defending.
##   fort    Stonegate (the neutral keep on the hills) in a game with sieges: the Crown from Westwatch, the Clans from
##           Thornvale. The garrison holds the ground in the open before its fort (SiegeRules: an "empty" open battle with
##           a holder), so the battle stands at the walls.
##   rivals  A Crown keep (Stonegate) the Clans besiege, when a third faction, the Wild Host (a copy of the Clans made for
##           the test, as tests/test_siege_battles.gd row 12 does), arrives and the garrison sallies: one open battle of all
##           three outside the walls, the garrison marching out of the gate.

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const HOLDS := IndependentData.FACTION_ID
const WILDS := "wilds"
const MAX_SEED := 40
const NAMES := ["holds", "fort", "rivals"]
## Each army the Crown and the Clans send: a front rank, a second rank and a commander.
const CROWN_ARMY := ["spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knights", "knight_captain"]
const CLANS_ARMY := ["tuskers", "tuskers", "tuskers", "fangthrowers", "fangthrowers", "war_bear", "warchief"]

static var _cache := {}


static func names() -> Array:
	return NAMES.duplicate()


## The fixture `name` ({} when there is none, or when no seed up to MAX_SEED shows it).
static func battle(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out := {}
	if NAMES.has(name):
		for sd in range(1, MAX_SEED + 1):
			var fought := fight(name, sd)
			if not fought.is_empty() and shows(fought.log):
				out = fought
				break
	_cache[name] = out
	return out


## Fights fixture `name` on turn seed `seed_value`: its battle as {"log", "report", ...}, or {} when the turn made none.
static func fight(name: String, seed_value: int) -> Dictionary:
	var setup := _setup(name)
	if setup.is_empty():
		return {}
	var result := TurnResolver.resolve(setup.state, setup.orders, seed_value, AutoBattleResolver.new())
	if result.new_state == null:
		return {}
	var pid := String(setup.province)
	for e in result.events:
		if e.type == "battle" and Array(e.provinces) == [pid] and (e.numbers.get("log", {}) as Dictionary).get("sides", []).size() == 3:
			return {"log": e.numbers.log, "report": e.numbers.report, "event": e, "state": result.new_state, "seats": setup.seats,
				"province": pid, "seed": seed_value}
	return {}


## Whether a three-sided battle shows what these fixtures are for: every side attacks in the first round, and no side is
## out before the second round has been fought (so every side is on the field for a while).
static func shows(battle_log: Dictionary) -> bool:
	var sides: Array = battle_log.get("sides", [])
	if sides.size() != 3:
		return false
	var attacked := {}
	for e in battle_log.events:
		if e.t == "attack" and int(e.n) == 1:
			attacked[int(battle_log.fighters[int(e.by)].side)] = true
		if (e.t == "rout" or e.t == "destroyed") and int(e.n) < 2:
			return false
	return attacked.size() == sides.size()


static func _setup(name: String) -> Dictionary:
	match name:
		"holds":
			var s := GameState.new(7)
			if not s.setup_independents([]):
				return {}
			_clear_players(s)
			_take(s, "greenglade", CLANS)
			var a := _army(s, CROWN, "crownkeep", CROWN_ARMY)
			var b := _army(s, CLANS, "greenglade", CLANS_ARMY)
			return {"state": s, "province": "rivermarch", "seats": [CROWN, CLANS],
				"orders": {CROWN: [MoveOrder.new(a.id, "rivermarch")], CLANS: [MoveOrder.new(b.id, "rivermarch")]}}
		"fort":
			var s2 := GameState.with_sieges(7)
			if not s2.setup_independents([]):
				return {}
			_clear_players(s2)
			_take(s2, "westwatch", CROWN)
			_take(s2, "thornvale", CLANS)
			var a2 := _army(s2, CROWN, "westwatch", CROWN_ARMY)
			var b2 := _army(s2, CLANS, "thornvale", CLANS_ARMY)
			return {"state": s2, "province": "stonegate", "seats": [CROWN, CLANS],
				"orders": {CROWN: [MoveOrder.new(a2.id, "stonegate")], CLANS: [MoveOrder.new(b2.id, "stonegate")]}}
		"rivals":
			var s3 := F.state([
				["kingdom-1", CROWN, "stonegate", ["spearmen", "spearmen", "spearmen", "crossbowmen"]],
				["kingdom-2", CROWN, "stonegate", ["crossbowmen", "knight_captain"]],
				["beasts-4", CLANS, "stonegate", ["tuskers", "tuskers", "tuskers", "fangthrowers", "warchief"], 1],
			], {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
			s3.current_turn = 5
			s3.find_province("stonegate").siege_since = 4
			_with_wilds(s3, "wilds-9", "thornvale", 4)
			return {"state": s3, "province": "stonegate", "seats": [CROWN, CLANS, WILDS],
				"orders": {WILDS: [MoveOrder.new("wilds-9", "stonegate")], CROWN: [SiegeOrder.sally("kingdom-1")]}}
	return {}


## Every army of the players gone (the Free Holds' garrisons stay), so the turn's only battles are the fixture's.
static func _clear_players(s: GameState) -> void:
	s.armies = s.armies.filter(func(a): return a.owner == HOLDS)


## `pid` becomes `fid`'s, its garrison gone (the way in its army marches from).
static func _take(s: GameState, pid: String, fid: String) -> void:
	s.find_province(pid).owner = fid
	s.armies = s.armies.filter(func(a): return a.id != IndependentData.army_id(pid))


static func _army(s: GameState, fid: String, at: String, type_ids: Array) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	var f := s.find_faction(fid)
	for type_id in type_ids:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			a.commander = Unit.new(ut, fid)
		else:
			a.units.append(Unit.new(ut, fid))
	s.armies.append(a)
	return a


## Adds a third faction, the Wild Host (the Clans' roster under another id, its capital at Deepwood), with one army of
## `bears` War Bears at `at` (tests/test_siege_battles.gd's _with_wilds).
static func _with_wilds(s: GameState, army_id: String, at: String, bears: int) -> void:
	var d := s.find_faction(CLANS).to_dict()
	d["id"] = WILDS
	d["name"] = "Wild Host"
	d["capital"] = "deepwood"
	var f := Faction.from_dict(d)
	f.gold = 45
	s.factions.append(f)
	var deep := s.find_province("deepwood")
	deep.is_capital = true
	deep.owner = WILDS
	s.find_province("thornvale").owner = WILDS
	var a := Army.new()
	a.id = army_id
	a.owner = WILDS
	a.location = at
	for i in bears:
		a.units.append(Unit.new(f.unit_types[2], WILDS))
	s.armies.append(a)
