class_name Unit
## Individual unit instance in an army.

var type: UnitType
var current_hp: int
var owner: String  # faction id

func _init(unit_type: UnitType, faction_id: String) -> void:
	type = unit_type
	current_hp = unit_type.hp
	owner = faction_id

func get_description() -> String:
	return "%s (%d/%d hp)" % [type.name, current_hp, type.hp]

func to_dict() -> Dictionary:
	return {
		"type_id": type.id,
		"current_hp": current_hp,
		"owner": owner,
	}

static func from_dict(data: Dictionary, all_unit_types: Dictionary) -> Unit:
	var type_id: String = data.get("type_id", "")
	var ut: UnitType = all_unit_types.get(type_id)
	if not ut:
		ut = UnitType.new()  # fallback
	var u := Unit.new(ut, data.get("owner", ""))
	u.current_hp = data.get("current_hp", ut.hp)
	return u
