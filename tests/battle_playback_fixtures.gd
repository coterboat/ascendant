extends RefCounted
## The battles the M3-3 playback tests run on: the twelve stored M3 fixtures (tests/fixtures/battles) and
## four battles with paths (M4-3, #83), fought here with the real resolver from tests/path_battle_fixtures.gd
## so they follow the rules as they are: a Wings dive at a commander, Iron Hide, a Lifedrinker heal and Red
## Harvest (fought through TurnResolver, so its log has the harvest and the aftermath). Each is
## {"log", "report"} (and "event" for Red Harvest). Built once per run and cached; every battle is
## seeded, so they are the same every time.

const Watch := preload("res://ui/battle/battle_watch.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const PB := preload("res://tests/path_battle_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const HOST := ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"]
const IRON := ["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"]
const PACT := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"]
const PATH_NAMES := ["path_wings", "path_iron_hide", "path_lifedrinker", "path_red_harvest"]

static var _cache := {}


## Every battle's name: the stored fixtures, then the path battles.
static func names() -> Array:
	return Scenarios.NAMES + PATH_NAMES


## {"log", "report"} of battle `name` ({} when there is no such battle).
static func battle(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out := {}
	match name:
		"path_wings":
			out = _first(HOST, CROWN, ["seraphs", "seraphs", "seraphs", "spearmen"], ["tuskers", "tuskers", "warchief"], "rivermarch", "",
				func(lg): return _wings_at_commander(lg))
		"path_iron_hide":
			out = _first(IRON, CROWN, ["iron_colossus"], ["fangthrowers", "fangthrowers", "fangthrowers"], "rivermarch", "",
				func(lg): return _has_iron_hide(lg))
		"path_lifedrinker":
			out = _first(PACT, CLANS, ["knights", "spearmen", "spearmen"], ["bloodsworn", "bloodsworn"], "rivermarch", "",
				func(lg): return lg.events.any(func(e): return e.t == "heal"))
		"path_red_harvest":
			out = _red_harvest()
		"massive":
			out = _massive()
		_:
			out = Watch.load_fixture(name)
	_cache[name] = out
	return out


## The first seed in 1..40 on which the battle shows what it is for: the Crown's `crown_ids` against the
## Clans' `clans_ids`, with `nodes` researched by `node_fid`.
static func _first(nodes: Array, node_fid: String, crown_ids: Array, clans_ids: Array, where: String, defender: String, shows: Callable) -> Dictionary:
	for sd in range(1, 41):
		var s := PB.with_nodes(PB.game(), node_fid, nodes)
		var a := PB.army(s, CROWN, "kingdom-1", where, crown_ids)
		var b := PB.army(s, CLANS, "beasts-2", where, clans_ids)
		var r := PB.fight(s, [a, b], where, defender, sd)
		if shows.call(r.log):
			return {"log": r.log, "report": r.result.report, "seed": sd}
	return {}


static func _wings_at_commander(lg: Dictionary) -> bool:
	for e in lg.events:
		if e.t == "attack" and e.reach == "wings" and lg.fighters[int(e.to)].role == "commander":
			return true
	return false


static func _has_iron_hide(lg: Dictionary) -> bool:
	for e in lg.events:
		if e.t == "attack" and e.hit and e.bonus.has(AutoBattleResolver.IRON_HIDE):
			return true
	return false


## A battle bigger than any measured one (#125, M3 3.4's files): 161 fighters a side, 322 in all, over the
## 3D stage's 1:1 limit of 280. The Crown holds Rivermarch. Not in names(): only the files tests and the
## launcher (--fixture massive) play it.
static func _massive() -> Dictionary:
	var s := PB.game()
	var crown := []
	for k in 90:
		crown.append("spearmen")
	for k in 50:
		crown.append("crossbowmen")
	for k in 20:
		crown.append("knights")
	crown.append("knight_captain")
	var clans := []
	for k in 80:
		clans.append("tuskers")
	for k in 60:
		clans.append("fangthrowers")
	for k in 20:
		clans.append("war_bear")
	clans.append("warchief")
	var a := PB.army(s, CROWN, "kingdom-1", "rivermarch", crown)
	var b := PB.army(s, CLANS, "beasts-2", "rivermarch", clans)
	var r := PB.fight(s, [a, b], "rivermarch", CROWN, 11)
	return {"log": r.log, "report": r.result.report, "seed": 11}


## A Red Harvest battle fought through TurnResolver (the gold, the harvest event and the aftermath).
static func _red_harvest() -> Dictionary:
	for sd in range(1, 21):
		var s := PB.with_nodes(PB.game(), CLANS, PACT)
		s.find_faction(CLANS).mandates = [AutoBattleResolver.RED_HARVEST]
		var a := PB.army(s, CLANS, "beasts-1", "bloodfen", ["tuskers", "tuskers", "tuskers", "war_bear"])
		var b := PB.army(s, CROWN, "kingdom-2", "bloodfen", ["spearmen", "crossbowmen"])
		var events := []
		var winner := TurnResolver._fight(s, AutoBattleResolver.new(), SeededRNG.new(sd), "province", ["bloodfen"],
			{CLANS: [a], CROWN: [b]}, CLANS, events)
		if winner == CLANS and not events.is_empty() and events[0].numbers.has("log"):
			var ev: Dictionary = events[0]
			return {"log": ev.numbers.log, "report": ev.numbers.report, "event": ev, "seed": sd}
	return {}
