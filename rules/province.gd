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

static func from_dict(data: Dictionary) -> Province:
	var p := Province.new()
	p.id = data.get("id", "")
	p.name = data.get("name", "")
	p.terrain = data.get("terrain", "")
	p.income = Serial.to_int(data.get("income", 0))
	p.neighbors = Serial.to_string_array(data.get("neighbors", []))
	p.owner = data.get("owner", "")
	p.is_capital = data.get("is_capital", false)
	p.has_fort = data.get("has_fort", false)
	return p
