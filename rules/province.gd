class_name Province
## Pure data for a province. No Node dependencies.
## Forts and sieges (M3c, design/M3C_SIEGES.md §12): a game with sieges (GameState.sieges) also keeps the
## fort's level and walls, its construction site, its siege and who has owned it since when. They are
## written by to_dict(true) only, so a game without sieges saves exactly as before. Rules: SiegeRules.

var id: String
var name: String
var terrain: String
var income: int = 0
var neighbors: Array = []
var owner: String = ""  # faction id or empty
var is_capital: bool = false
var has_fort: bool = false  # with sieges on it is true exactly when fort_level is 1 or more

# --- forts and sieges (M3c): only in a game with sieges, and only saved there ---
var fort_level: int = 0  # 0 none, 1 palisade, 2 keep, 3 citadel (FortData.LEVELS)
var walls: int = 0  # wall strength, 0..the level's maximum; 0 at a fort is a breach
var fort_by: String = ""  # the faction that built the current level ("" for a fort on the map)
var works: Dictionary = {}  # a construction site: {} or {"faction", "to" (level), "left" (turns of work), "turn" (ordered)}
var siege_since: int = 0  # the turn (as players count) the current siege began; 0 when there is none
var owned_since: int = 0  # the turn its owner took it; 0 for owners from the start and for neutral provinces
var lost: Dictionary = {}  # {} or {"faction", "owned_since", "turn"}: who lost it last, for the retake rule

func get_description() -> String:
	return "%s (%s, income %d)" % [name, terrain, income]

# Province stat descriptions per acceptance criterion
static func describe(stat: String) -> String:
	match stat:
		"terrain": return "Type of land affecting movement, defense, and income."
		"income": return "Gold generated each turn for the owner."
		"fort": return "Defensive structure providing combat bonus."
		"capital": return "Key province; losing it ends the game."
		_: return ""

## `sieges` (GameState.to_dict passes GameState.sieges) adds the fort and siege fields; without it they are
## left out, so a game without sieges saves exactly as before.
func to_dict(sieges: bool = false) -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"terrain": terrain,
		"income": income,
		"neighbors": neighbors.duplicate(),
		"owner": owner,
		"is_capital": is_capital,
		"has_fort": has_fort,
	}
	if sieges:
		d["fort_level"] = fort_level
		d["walls"] = walls
		d["fort_by"] = fort_by
		d["works"] = works.duplicate()
		d["siege_since"] = siege_since
		d["owned_since"] = owned_since
		d["lost"] = lost.duplicate()
	return d

## Returns null when a field has the wrong type, with a plain-language reason in `errors` (Serial
## load checks). `who` names the province in it; GameState.from_dict passes "province 'crownkeep'".
static func from_dict(data: Dictionary, errors = null, who: String = "") -> Province:
	if who.is_empty():
		who = Serial.label("province", data)
	var p := Province.new()
	for key in ["id", "name", "terrain", "owner"]:
		var text = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if text == null:
			return null
		p.set(key, String(text))
	for key in ["is_capital", "has_fort"]:
		var flag = Serial.expect(data, key, TYPE_BOOL, errors, who, false)
		if flag == null:
			return null
		p.set(key, flag)
	var neighbors = Serial.expect(data, "neighbors", TYPE_ARRAY, errors, who, [])
	if neighbors == null:
		return null
	p.neighbors = Serial.to_string_array(neighbors)
	p.income = Serial.to_int(data.get("income", 0))
	# Forts and sieges (M3c): only a game with sieges carries these; GameState.validate checks them.
	var fort_by = Serial.expect(data, "fort_by", TYPE_STRING, errors, who, "")
	if fort_by == null:
		return null
	p.fort_by = String(fort_by)
	for key in ["works", "lost"]:
		var group = Serial.expect(data, key, TYPE_DICTIONARY, errors, who, {})
		if group == null:
			return null
		p.set(key, _int_fields(group, ["to", "left", "turn", "owned_since"]))
	for key in ["fort_level", "walls", "siege_since", "owned_since"]:
		p.set(key, Serial.to_int(data.get(key, 0)))
	return p


## A copy of `group` with the listed number fields read back as ints (after a JSON round trip they are
## floats) and every other field as text.
static func _int_fields(group: Dictionary, int_keys: Array) -> Dictionary:
	var out := {}
	for key in group:
		out[str(key)] = Serial.to_int(group[key]) if int_keys.has(str(key)) else str(group[key])
	return out
