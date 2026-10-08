extends RefCounted
## Siege battles for the 3D stage's tests and screenshots (M3c S-5, #103): a storm at a keep, a palisade and a
## capital, the breach, and the open battles (a sally, a relief, a relief with a sally, the gate battle), each
## fought with the real AutoBattleResolver through TurnResolver, so the logs carry the real `siege` block.
## Each is {"log", "report", "event", "province", "garrison"} (the battle event; the stage's `show_event` takes it).
## Built once per run and cached. Not a test file itself (the runner only runs test_*.gd).

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"

## Where each faction's relief comes from, and the units its garrison and its stormers are made of.
const HOME := {"stonegate": "westwatch", "westwatch": "crownkeep", "crownkeep": "rivermarch", "blackwood": "ebonpeak",
	"ebonpeak": "fangridge", "fangridge": "bloodfen"}
const GARRISON := {
	CROWN: [["spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen"], ["crossbowmen", "crossbowmen", "knight_captain"]],
	CLANS: [["tuskers", "tuskers", "tuskers", "fangthrowers", "fangthrowers"], ["fangthrowers", "fangthrowers", "warchief"]],
}
const STORMERS := {
	CROWN: ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knight_captain"],
	CLANS: ["tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers", "fangthrowers", "warchief"],
}

## name -> {"pid": province, "level": fort level, "walls": walls (-1 full), "owner": the garrison's faction, "strong": the
## armies given a big force, "orders": what each side orders, "index": which of that province's battles}.
## Stonegate and Blackwood are map keeps on hills (kingdom and beasts kits), Westwatch and Ebonpeak have no fort on the map
## (a palisade there is built), Crownkeep and Fangridge are the capitals (citadels, drawn as the world's fortresses).
const CASES := {
	"storm_keep": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": [], "orders": "storm", "index": 0},
	"storm_keep_low": {"pid": "stonegate", "level": 2, "walls": 2, "owner": CROWN, "strong": [], "orders": "storm", "index": 0},
	"storm_keep_beasts": {"pid": "blackwood", "level": 2, "walls": -1, "owner": CLANS, "strong": [], "orders": "storm", "index": 0},
	"storm_palisade": {"pid": "westwatch", "level": 1, "walls": -1, "owner": CROWN, "strong": [], "orders": "storm", "index": 0},
	"storm_palisade_beasts": {"pid": "ebonpeak", "level": 1, "walls": -1, "owner": CLANS, "strong": [], "orders": "storm", "index": 0},
	"storm_capital": {"pid": "crownkeep", "level": 3, "walls": -1, "owner": CROWN, "strong": [], "orders": "storm", "index": 0},
	"storm_capital_battered": {"pid": "crownkeep", "level": 3, "walls": 3, "owner": CROWN, "strong": [], "orders": "storm", "index": 0},
	"storm_capital_beasts": {"pid": "fangridge", "level": 3, "walls": -1, "owner": CLANS, "strong": [], "orders": "storm", "index": 0},
	"storm_won": {"pid": "stonegate", "level": 2, "walls": 2, "owner": CROWN, "strong": ["stormers"], "orders": "storm", "index": 0},
	"breach": {"pid": "stonegate", "level": 2, "walls": 0, "owner": CROWN, "strong": [], "orders": "none", "index": 0},
	"breach_beasts": {"pid": "blackwood", "level": 2, "walls": 0, "owner": CLANS, "strong": [], "orders": "none", "index": 0},
	"breach_palisade": {"pid": "westwatch", "level": 1, "walls": 0, "owner": CROWN, "strong": [], "orders": "none", "index": 0},
	"breach_capital": {"pid": "crownkeep", "level": 3, "walls": 0, "owner": CROWN, "strong": [], "orders": "none", "index": 0},
	"sally": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": [], "orders": "sally", "index": 0},
	"sally_beasts": {"pid": "blackwood", "level": 2, "walls": -1, "owner": CLANS, "strong": [], "orders": "sally", "index": 0},
	"sally_capital": {"pid": "crownkeep", "level": 3, "walls": -1, "owner": CROWN, "strong": [], "orders": "sally", "index": 0},
	"relief": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": [], "orders": "relief", "index": 0},
	"relief_sally": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": [], "orders": "relief_sally", "index": 0},
	"gate": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": ["stormers"], "orders": "gate", "index": 0},
	"storm_after_gate": {"pid": "stonegate", "level": 2, "walls": -1, "owner": CROWN, "strong": ["stormers"], "orders": "gate", "index": 1},
}

static var _cache := {}


static func names() -> Array:
	return CASES.keys()


## The fixture `name` ({} when there is none, or when the turn made no such battle).
static func battle(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	if not CASES.has(name):
		return {}
	var c: Dictionary = CASES[name]
	var pid: String = c.pid
	var s := state(pid, int(c.level), int(c.walls), String(c.owner), c.strong)
	var r := F.resolve(s, orders(String(c.orders), pid, String(c.owner)), true)
	var battles: Array = r.events.filter(func(e): return e.type == "battle" and e.provinces == [pid])
	var out := {}
	if battles.size() > int(c.index):
		var b: Dictionary = battles[int(c.index)]
		out = {"log": b.numbers.log, "report": b.numbers.report, "event": b, "province": pid, "garrison": String(c.owner), "state": r.new_state}
	_cache[name] = out
	return out


static func other(faction: String) -> String:
	return CLANS if faction == CROWN else CROWN


## Turn 6 is being ordered. `owner` holds `pid` with two armies inside (its first and second, ids "<faction>-1" and "-2"), a
## relief army "<faction>-3" at the province next toward home; the other faction's army "<other>-4" (with 2 siege engines)
## has besieged it since turn 4. `strong` names the armies given a big force: "garrison", "stormers".
static func state(pid: String, level: int, walls: int, owner: String, strong: Array = []) -> GameState:
	var foe := other(owner)
	var home: String = HOME[pid]
	var g: Array = GARRISON[owner]
	var first: Array = g[0]
	var second: Array = g[1]
	var big := "knights" if owner == CROWN else "war_bear"
	var attack: Array = STORMERS[foe]
	if strong.has("stormers"):
		attack = F.units("war_bear" if foe == CLANS else "knights", 8)
	var s := F.state([
		["%s-1" % owner, owner, pid, F.units(big, 6) if strong.has("garrison") else first],
		["%s-2" % owner, owner, pid, second],
		["%s-3" % owner, owner, home, F.units("knights" if owner == CROWN else "tuskers", 2)],
		["%s-4" % foe, foe, pid, attack, 2],
	], {pid: owner, home: owner, "blackwood" if pid == "stonegate" else "stonegate": foe})
	s.current_turn = 5
	F.set_fort(s, pid, level, walls)
	s.find_province(pid).siege_since = 4
	return s


static func orders(kind: String, pid: String, owner: String) -> Dictionary:
	var foe := other(owner)
	var storm := SiegeOrder.storm(pid)
	var relief := MoveOrder.new("%s-3" % owner, pid)
	match kind:
		"storm":
			return {foe: [storm]}
		"sally":
			return {owner: [SiegeOrder.sally("%s-1" % owner)]}
		"relief":
			return {owner: [relief]}
		"relief_sally":
			return {owner: [relief, SiegeOrder.sally("%s-1" % owner, "%s-3" % owner)]}
		"gate":
			return {foe: [storm], owner: [SiegeOrder.sally("%s-1" % owner)]}
	return {}
