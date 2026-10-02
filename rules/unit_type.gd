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
## A ruler's stats (M2): built by RulerRules from the ruler and its kept power, never recruited
## (cost 0, no trait). Rulers are not "units" for mandates and traits that name units.
var is_ruler: bool = false

# Short plain-language descriptions for tooltips/codex. Matches acceptance criterion for every stat.
static func describe(stat: String) -> String:
	match stat:
		"hp": return "Hit points. Reduced by damage in battle."
		"attack": return "How dangerous its strikes are. The higher its attack is above the target's defense, the more likely each attack is to hit, and a higher attack deals more damage with every hit."
		"defense": return "How hard it is to hurt. The higher its defense is above the attacker's attack, the less likely an attack is to hit it, and every hit that lands deals less damage."
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
	var d := {
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
	if is_ruler:
		d["is_ruler"] = true  # only rulers carry the key, so M1 data saves exactly as before
	return d

## Returns null when a field has the wrong type, with a plain-language reason in `errors` (Serial load
## checks). `who` names the unit type in it; Faction.from_dict passes "unit type 2 of faction 'kingdom'".
static func from_dict(data: Dictionary, errors = null, who: String = "") -> UnitType:
	if who.is_empty():
		who = Serial.label("unit type", data)
	var text := {}
	for key in ["id", "name", "trait", "trait_description", "trait_desc"]:
		text[key] = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if text[key] == null:
			return null
	var flags := {}
	for key in ["is_commander", "is_ruler"]:
		flags[key] = Serial.expect(data, key, TYPE_BOOL, errors, who, false)
		if flags[key] == null:
			return null
	var ut := UnitType.new()
	ut.id = text.id
	ut.name = text.name
	ut.hp = Serial.to_int(data.get("hp", 10), 10)
	ut.attack = Serial.to_int(data.get("attack", 5), 5)
	ut.defense = Serial.to_int(data.get("defense", 5), 5)
	ut.morale = Serial.to_int(data.get("morale", 5), 5)
	ut.cost = Serial.to_int(data.get("cost", 10), 10)
	ut.trait_id = text.trait
	ut.trait_description = text.trait_description if data.has("trait_description") else text.trait_desc
	ut.is_commander = flags.is_commander
	ut.is_ruler = flags.is_ruler
	return ut
