class_name UnitType
## Stats template for units and commanders. Every stat has a tooltip description.

var id: String
var name: String
var hp: int = 10
var attack: int = 5
var defense: int = 5
var morale: int = 5
var cost: int = 10
var trait_id: String = ""
var trait_description: String = ""
var is_commander: bool = false

# Short plain-language descriptions for tooltips/codex. Matches acceptance criterion for every stat.
static func describe(stat: String) -> String:
	match stat:
		"hp": return "Hit points. Reduced by damage in battle."
		"attack": return "Damage dealt per attack round."
		"defense": return "Damage reduction per hit received."
		"morale": return "Resistance to routing and morale checks."
		"cost": return "Gold cost to recruit."
		"trait": return "Special ability or unique mechanic."
		_: return ""

func get_hp_desc() -> String: return describe("hp")
func get_attack_desc() -> String: return describe("attack")
func get_defense_desc() -> String: return describe("defense")
func get_morale_desc() -> String: return describe("morale")
func get_cost_desc() -> String: return describe("cost")
func get_trait_desc() -> String: return trait_description if not trait_description.is_empty() else describe("trait")

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"hp": hp,
		"attack": attack,
		"defense": defense,
		"morale": morale,
		"cost": cost,
		"trait": trait_id,
		"trait_description": trait_description,
		"is_commander": is_commander,
	}

static func from_dict(data: Dictionary) -> UnitType:
	var ut := UnitType.new()
	ut.id = data.get("id", "")
	ut.name = data.get("name", "")
	ut.hp = Serial.to_int(data.get("hp", 10), 10)
	ut.attack = Serial.to_int(data.get("attack", 5), 5)
	ut.defense = Serial.to_int(data.get("defense", 5), 5)
	ut.morale = Serial.to_int(data.get("morale", 5), 5)
	ut.cost = Serial.to_int(data.get("cost", 10), 10)
	ut.trait_id = data.get("trait", "")
	ut.trait_description = data.get("trait_description", data.get("trait_desc", ""))
	ut.is_commander = data.get("is_commander", false)
	return ut
