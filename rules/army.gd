class_name Army
## Army belonging to a faction, located in a province, containing units and a commander.
## M2: a ruler travels alone, as its own army (design/M2_RULER.md §1.5): an army with a `ruler` holds
## no units and no commander (GameState.validate checks it). Rules and labels: RulerRules.

var id: String  # unique within a GameState, e.g. "kingdom-1"; orders refer to armies by id
var owner: String
var location: String  # province id
var units: Array[Unit] = []
var commander: Unit = null
var ruler: Unit = null  # the faction's living ruler (its type is the faction's ruler_unit_type), or null

func get_description() -> String:
	if ruler:
		return "%s ruler %s at %s" % [owner, ruler.type.name, location]
	var desc := "%s army at %s with %d units" % [owner, location, units.size()]
	if commander:
		desc += " led by %s" % commander.type.name
	return desc

func to_dict() -> Dictionary:
	var unit_dicts := []
	for u in units:
		unit_dicts.append(u.to_dict())
	
	var cmd_dict := {}
	if commander:
		cmd_dict = commander.to_dict()
	
	var d := {
		"id": id,
		"owner": owner,
		"location": location,
		"units": unit_dicts,
		"commander": cmd_dict,
	}
	if ruler:
		d["ruler"] = ruler.to_dict()  # only ruler armies carry the key, so M1 armies save as before
	return d

## Returns null when the army is in an unknown province, holds an unknown unit type, or a field has the
## wrong type, with a plain-language reason in `errors` (Serial load checks). `who` names the army in
## it; GameState.from_dict passes "army 'kingdom-1'".
static func from_dict(data: Dictionary, all_unit_types: Dictionary, province_ids: Dictionary, errors = null, who: String = "") -> Army:
	if who.is_empty():
		who = Serial.label("army", data)
	var a := Army.new()
	for key in ["id", "owner", "location"]:
		var text = Serial.expect(data, key, TYPE_STRING, errors, who, "")
		if text == null:
			return null
		a.set(key, String(text))
	if not province_ids.has(a.location):
		Serial.report(errors, "%s is at '%s', which is not a province on this map." % [Serial.cap(who), a.location])
		return null

	var unit_list = Serial.expect_dicts(data, "units", errors, who, "unit")
	if unit_list == null:
		return null
	for i in unit_list.size():
		var unit := Unit.from_dict(unit_list[i], all_unit_types, errors, "unit %d of %s" % [i + 1, who])
		if unit == null:
			return null
		a.units.append(unit)

	var cmd_data = Serial.expect(data, "commander", TYPE_DICTIONARY, errors, who, {})  # {} when it has none
	if cmd_data == null:
		return null
	if not cmd_data.is_empty():
		a.commander = Unit.from_dict(cmd_data, all_unit_types, errors, "the commander of %s" % who)
		if a.commander == null:
			return null

	# Only a ruler's army has the key. The ruler's type is its faction's ruler_unit_type, which
	# GameState.from_dict puts in all_unit_types under the ruler's id before loading armies.
	var ruler_data = Serial.expect(data, "ruler", TYPE_DICTIONARY, errors, who, {})
	if ruler_data == null:
		return null
	if not ruler_data.is_empty():
		a.ruler = Unit.from_dict(ruler_data, all_unit_types, errors, "the ruler of %s" % who)
		if a.ruler == null:
			return null

	return a
