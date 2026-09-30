class_name Faction
## Pure faction data.

var id: String
var faction_name: String
var gold: int = 0
var capital: String = ""

var unit_types: Array[UnitType] = []
var commander_type: UnitType = null

func get_description() -> String:
	return faction_name

# Faction stat descriptions per acceptance criterion
static func describe(stat: String) -> String:
	match stat:
		"gold": return "Current treasury. Used to recruit units and commanders."
		_: return ""

func to_dict() -> Dictionary:
	var ut_dicts := []
	for ut in unit_types:
		ut_dicts.append(ut.to_dict())
	
	return {
		"id": id,
		"name": faction_name,
		"gold": gold,
		"capital": capital,
		"unit_types": ut_dicts,
		"commander_type": commander_type.to_dict() if commander_type else {},
	}

static func from_dict(data: Dictionary) -> Faction:
	var f := Faction.new()
	f.id = data.get("id", "")
	f.faction_name = data.get("name", "")
	f.gold = Serial.to_int(data.get("gold", 0))
	f.capital = data.get("capital", "")
	
	if data.has("unit_types"):
		for u in data.unit_types:
			f.unit_types.append(UnitType.from_dict(u))
	
	if data.has("commander_type") and not data.commander_type.is_empty():
		f.commander_type = UnitType.from_dict(data.commander_type)
	
	return f
