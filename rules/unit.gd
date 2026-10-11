class_name Unit
## Individual unit instance in an army.

var type: UnitType
var current_hp: int
var owner: String  # faction id
## M5 magic (design/M5_MAGIC_FOG.md §6.4): the turn a summoned creature fades, or 0 (every other unit, and the
## Greenwrath, which stays until it falls). Only summoned units carry one (MagicRules.validate); saved only when not 0.
var until: int = 0
## ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): per-unit statuses, each {"kind", "source", ...} (UnitStatus is the
## registry: ARM-1 ships "outside_blessing"). Saved only when not empty, as `until` is, so every existing record
## and save is byte-identical.
var statuses: Array = []

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
	if not statuses.is_empty():
		d["statuses"] = UnitStatus.to_list(statuses)  # ARM-1: only a unit with a status carries the key
	return d


## Whether this unit has a status of `kind` (from `source` when given).
func has_status(kind: String, source: String = "") -> bool:
	for s in statuses:
		if String(s.kind) == kind and (source.is_empty() or String(s.get("source", "")) == source):
			return true
	return false


## Adds a status {"kind", "source", ...}; false (and no change) when this unit already has that kind from that source.
func add_status(kind: String, source: String, extra: Dictionary = {}) -> bool:
	if has_status(kind, source):
		return false
	var status := {"kind": kind, "source": source}
	for key in extra:
		status[key] = extra[key]
	statuses.append(UnitStatus.normalize(status))
	return true


## Removes the statuses of `kind` (those from `source` only when given). Returns how many it removed.
func remove_status(kind: String, source: String = "") -> int:
	var kept := []
	var n := 0
	for s in statuses:
		if String(s.kind) == kind and (source.is_empty() or String(s.get("source", "")) == source):
			n += 1
		else:
			kept.append(s)
	statuses = kept
	return n

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
	var listed = data.get("statuses")  # ARM-1: absent or null means none
	if listed != null:
		var parsed = UnitStatus.parse_list(listed, errors, who)
		if parsed == null:
			return null
		u.statuses = parsed
	return u
