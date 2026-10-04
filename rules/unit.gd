class_name Unit
## Individual unit instance in an army.

var type: UnitType
var current_hp: int
var owner: String  # faction id
## M5 magic (design/M5_MAGIC_FOG.md §6.4): the turn a summoned creature fades, or 0 (every other unit, and the
## Greenwrath, which stays until it falls). Only summoned units carry one (MagicRules.validate); saved only when not 0.
var until: int = 0

func _init(unit_type: UnitType, faction_id: String) -> void:
	type = unit_type
	current_hp = unit_type.hp
	owner = faction_id

func get_description() -> String:
	return "%s (%d/%d hp)" % [type.name, current_hp, type.hp]

func to_dict() -> Dictionary:
	var d := {
		"type_id": type.id,
		"current_hp": current_hp,
		"owner": owner,
	}
	if until != 0:
		d["until"] = until  # M5: only a summoned creature that fades carries the key
	return d

## Returns null when its type is unknown or a field has the wrong type, with a plain-language reason in
## `errors` (Serial load checks). `who` names the unit in it ("unit 2 of army 'kingdom-1'").
static func from_dict(data: Dictionary, all_unit_types: Dictionary, errors = null, who: String = "a unit") -> Unit:
	var type_id = Serial.expect(data, "type_id", TYPE_STRING, errors, who, "")
	if type_id == null:
		return null
	var owner = Serial.expect(data, "owner", TYPE_STRING, errors, who, "")
	if owner == null:
		return null
	var ut: UnitType = all_unit_types.get(String(type_id))
	if not ut:
		Serial.report(errors, "%s has unit type '%s', which is not a unit type in this game." % [Serial.cap(who), type_id])
		return null
	var u := Unit.new(ut, String(owner))
	u.current_hp = Serial.to_int(data.get("current_hp", ut.hp), ut.hp)
	u.until = Serial.to_int(data.get("until", 0))
	return u
