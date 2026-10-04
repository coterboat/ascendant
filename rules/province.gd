class_name Province
## Pure data for a province. No Node dependencies.

var id: String
var name: String
var terrain: String
var income: int = 0
var neighbors: Array = []
var owner: String = ""  # faction id or empty
var is_capital: bool = false
var has_fort: bool = false

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

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"terrain": terrain,
		"income": income,
		"neighbors": neighbors.duplicate(),
		"owner": owner,
		"is_capital": is_capital,
		"has_fort": has_fort,
	}

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
	return p
