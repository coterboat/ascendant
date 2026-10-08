extends RefCounted
## Battles with every battle spell for the 3D stage's tests and screenshots (M5-9, #120), fought with the real resolver on top
## of tests/magic_battle_fixtures.gd: a field battle where all five spells are cast in round 1 ("all"), one for each spell, the
## Blood Moon's heals, and a 280-fighter battle with 6 casters for the performance check. Each is {"log", "report", "state"}
## (the stage's play() takes them as watch() does: the game they were fought in comes along). Built once per run and cached,
## every battle seeded, so it is the same every time. Not a test file itself (the runner only runs test_*.gd).
##
##   godot --path . -- --battle3d --fixture magic_all       (world3d/battle_watch3d.gd loads these by their "magic_" names)

const MB := preload("res://tests/magic_battle_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const NAMES := ["magic_all", "magic_sunlance", "magic_sunburst", "magic_shield", "magic_snare", "magic_bloodbolt", "magic_moon", "magic_pack", "magic_big"]
## Everything the Crown's three spells need (the Oath of the Dawn opens Sunburst), the Clans' two, and the Blood Moon's pact.
const CROWN_NODES := ["crown_drillyard", "crown_charters", "crown_oath_dawn", "sunlance", "dawn_blessing", "sunburst", "shield_of_law"]
const CLANS_NODES := ["briar_snare", "bloodbolt"]
const PACT := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"]
const WHERE := "rivermarch"

static var _cache := {}


## {"log", "report", "state"} of battle `name` ({} when there is none).
static func battle(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out := {}
	match name:
		"magic_all":
			out = _field(CROWN_NODES, CLANS_NODES, [], 5, true, 17, 16)
		"magic_sunlance":
			out = _field(["sunlance"], [], ["sunlance"], 5, true, 12, 12)
		"magic_sunburst":
			out = _field(CROWN_NODES, [], ["sunburst", "sunlance", "shield_of_law"], 5, false, 14, 14)
		"magic_shield":
			out = _field(CROWN_NODES, [], ["shield_of_law", "sunlance", "sunburst"], 5, false, 14, 14)
		"magic_snare":
			out = _field([], CLANS_NODES, ["briar_snare", "bloodbolt"], 5, false, 12, 14)
		"magic_bloodbolt":
			out = _field([], CLANS_NODES, ["bloodbolt", "briar_snare"], 5, false, 12, 14)
		"magic_moon":
			out = _moon()
		"magic_pack":
			out = _pack()
		"magic_big":
			out = _big()
	_cache[name] = out
	return out


## A field battle at Rivermarch: the Crown (the Ever-Regent when `regent`, three Adepts, spearmen, knights) against the Clans (two
## Shamans, tuskers, war bears). `crown_book` is the Crown's spellbook order when it is not the default.
static func _field(crown_nodes: Array, clans_nodes: Array, crown_book: Array, seed_value: int, regent: bool, crown_n: int, clans_n: int) -> Dictionary:
	var s := MB.game({CROWN: MB.REGENT if regent else MB.KING, CLANS: MB.AVATAR})
	if not crown_nodes.is_empty():
		s = MB.with_nodes(s, CROWN, crown_nodes)
	if not clans_nodes.is_empty():
		s = MB.with_nodes(s, CLANS, clans_nodes)
	if not crown_book.is_empty():
		MB.spellbook(s, CROWN, crown_book, [] if crown_book.has("sunlance") else ["sunlance"])
	var armies := []
	if regent:
		armies.append(MB.ruler_at(s, CROWN, WHERE, 3))
	var crown := ["knight_captain", "adepts", "adepts", "adepts"]
	for i in crown_n - 6:
		crown.append("spearmen" if i % 4 != 3 else "knights")
	crown.append("crossbowmen")
	crown.append("crossbowmen")
	armies.append(MB.army(s, CROWN, "kingdom-1", WHERE, crown))
	var clans := ["warchief", "shamans", "shamans"]
	for i in clans_n - 3:
		clans.append("tuskers" if i % 3 != 2 else "war_bear")
	armies.append(MB.army(s, CLANS, "beasts-2", WHERE, clans))
	return _fought(s, armies, seed_value)


## The Clans under the Blood Moon, with Lifedrinker (the pact), fighting the Crown: the moon's heals.
static func _moon() -> Dictionary:
	var s := MB.with_nodes(MB.game(), CLANS, PACT)
	MB.enchant(s, "blood_moon", CLANS)
	var a := MB.army(s, CROWN, "kingdom-1", WHERE, ["spearmen", "spearmen", "spearmen", "spearmen", "knights", "knights", "knight_captain"])
	var b := MB.army(s, CLANS, "beasts-2", WHERE, ["tuskers", "tuskers", "tuskers", "bloodsworn", "bloodsworn", "fangthrowers", "warchief"])
	return _fought(s, [a, b], 3)


## The Clans with their summons (five Thornwolves and the Greenwrath) and two Shamans against the Crown's Adepts: the four new figures.
static func _pack() -> Dictionary:
	var s := MB.with_nodes(MB.game({CROWN: MB.KING, CLANS: MB.AVATAR}), CLANS, CLANS_NODES)
	s = MB.with_nodes(s, CROWN, ["sunlance", "shield_of_law"])
	var a := MB.army(s, CROWN, "kingdom-1", WHERE, ["spearmen", "spearmen", "spearmen", "spearmen", "knights", "knights", "adepts", "adepts", "knight_captain"])
	var b := MB.army(s, CLANS, "beasts-2", WHERE, ["warchief", "shamans", "shamans", "tuskers", "tuskers", "thornwolves", "thornwolves", "thornwolves",
		"thornwolves", "thornwolves", "greenwrath"])
	return _fought(s, [a, b], 4)


## 280 fighters and 6 casters (the Regent, three Adepts, two Shamans): the performance check's battle.
static func _big() -> Dictionary:
	var s := MB.game({CROWN: MB.REGENT, CLANS: MB.AVATAR})
	s = MB.with_nodes(s, CROWN, CROWN_NODES)
	s = MB.with_nodes(s, CLANS, CLANS_NODES)
	var reg := MB.ruler_at(s, CROWN, WHERE, 3)
	var crown := ["knight_captain", "adepts", "adepts", "adepts"]
	for i in 150:
		crown.append(["spearmen", "spearmen", "crossbowmen", "knights"][i % 4])
	var clans := ["warchief", "shamans", "shamans"]
	for i in 122:
		clans.append(["tuskers", "tuskers", "fangthrowers", "war_bear"][i % 4])
	var a := MB.army(s, CROWN, "kingdom-1", WHERE, crown)
	var b := MB.army(s, CLANS, "beasts-2", WHERE, clans)
	return _fought(s, [reg, a, b], 5)


static func _fought(s: GameState, armies: Array, seed_value: int) -> Dictionary:
	var r := MB.fight(s, armies, WHERE, "", seed_value)
	return {"log": r.log, "report": r.result.report, "state": s}
